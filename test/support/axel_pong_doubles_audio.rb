require_relative "../../lib/axel_pong/audio"

class DoublesAudioSound
  attr_accessor :frequency, :volume, :pan, :position
  attr_reader :plays

  def initialize(name, played)
    @name, @played = name, played
    @frequency, @volume, @pan, @plays = 44100, 0, 0, 0
  end

  def play
    @playing = true
    @plays += 1
    @played << @name
  end

  def pause; @playing = false; end
  def playing?; @playing; end
  def finished?; !playing?; end
  def length; 2.0; end
  def close; pause; end
end

class DoublesAudioProgram
  attr_reader :sounds, :played
  attr_accessor :pong_preferences, :sound_gain

  def initialize
    @sounds, @played = {}, []
    @sound_gain = 1.0
    @voices = Hash.new { |h, key| h[key] = [] }
    @pong_preferences = GameRoomPong::Preferences::DEFAULTS.dup
  end

  def create_sound_from_asset(name, loop:)
    sound = DoublesAudioSound.new(name, @played)
    @sounds[name] ||= sound
    @voices[name] << sound
    sound
  end

  def voice(name, source); @voices.fetch(name).fetch(source); end
  def game_room_sound_volume(_asset); @sound_gain; end
end

def assert(value, message)
  raise message unless value
end

def near(actual, expected, message)
  assert((actual - expected).abs < 0.000001, "#{message}: #{actual} != #{expected}")
end

def rendered_pan(delta)
  pan = (Math.sqrt([delta.abs / 25.0, 1.0].min) * (delta.negative? ? -100 : 100)).to_i / 100.0
  pan.negative? ? (1 + pan)**1.4 - 1 : 1 - (1 - pan)**1.4
end

def identity_pitch(teams, source)
  teams.take(source).include?(teams[source]) ? 1.0 : 2.0**(-4.0 / 12)
end

def step_asset(teams, source, viewer)
  return 'pong_move_double' unless teams.take(source).include?(teams[source])
  teams[source] == teams[viewer] ? 'pong_move' : 'pong_op_move'
end

def movement_sample_gain(asset)
  asset == 'pong_move_double' ? 0.7079457843841379 : 1.0
end

def snapshot(teams)
  {'teams' => teams, 'p' => [5.0, 10.0, 20.0, 25.0],
    'b' => {'x' => 15.0, 'y' => 5.0, 'dy' => 1.0}, 'fx' => [], 'invisible' => false}
end

def with_audio(clock: -> { 0.0 })
  program = DoublesAudioProgram.new
  audio = GameRoomPong::Audio.new(program, clock: clock, rng: Random.new(17))
  audio.load
  audio.prepare_players(4)
  yield audio, program
ensure
  audio&.close
end
