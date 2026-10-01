require_relative "../../../lib/axel_pong/audio"
require_relative "../../../lib/axel_pong/engine"

class SourceSound
  attr_accessor :pan, :volume, :frequency, :position
  attr_reader :plays
  def initialize; @frequency = 44100; @plays = 0; end
  def play; @plays += 1; @playing = true; end
  def pause; @playing = false; end
  def playing?; @playing; end
  def close; end
end
class SourceAudioProgram
  attr_reader :sounds
  attr_accessor :pong_preferences
  def initialize
    @sounds = {}; @pong_preferences = GameRoomPong::Preferences::DEFAULTS.dup
  end
  def create_sound_from_asset(name, loop:); @sounds[name] = SourceSound.new; end
end
def near(a, b); raise "#{a} != #{b}" unless (a-b).abs < 0.000001; end
failures = []
check = lambda do |name, &body|
  body.call; puts "PASS #{name}"
rescue StandardError => error
  failures << "#{name}: #{error.message}"
end
require_relative "../../../lib/axel_pong/preferences"
p = SourceAudioProgram.new
a = GameRoomPong::Audio.new(p); a.load
check.call('R04: panorama scaled to 25 and truncated to integer percent') do
  [-28, -7, -0.1, 0, 0.1, 7, 28].each do |delta|
    expected = (Math.sqrt([delta.abs / 25.0, 1].min) * (delta < 0 ? -100 : 100)).to_i / 100.0
    near(a.send(:spatial, 15, 15 + delta, 0, 0)[0], expected)
  end
end
check.call('R05: power-law stereo, including clipping and silence') do
  [-1, -0.75, -0.25, 0, 0.25, 0.75, 1].product([0, 0.2, 0.5, 1, 2]).each do |pan, volume|
    sound = a.send(:play_sound, 'pong_wall', pan: pan, level: volume)
    left = sound.volume * (sound.pan > 0 ? 1-sound.pan : 1)
    right = sound.volume * (sound.pan < 0 ? 1+sound.pan : 1)
    near(left, [volume * (pan > 0 ? (1-pan)**1.4 : 1), 1].min)
    near(right, [volume * (pan < 0 ? (1+pan)**1.4 : 1), 1].min)
  end
end
check.call('R06: ringing wall follows the ball without replaying') do
  state = GameRoomPong::Engine.new.snapshot
  state['b'].merge!('x' => 29, 'y' => 5, 'dy' => 1)
  state['fx'] = [[1, 'wall', nil, 29, 5]]
  a.update(state, viewer: 0, paused: false)
  sound = p.sounds['pong_wall']; plays = sound.plays
  near(sound.volume, 0.8)
  state['b'].merge!('x' => 3, 'y' => 15)
  state['fx'] = []
  a.update(state, viewer: 0, paused: false)
  near(sound.volume, 0.4)
  raise 'wall pan frozen' unless sound.pan < 0
  raise 'wall restarted' unless sound.plays == plays
end
check.call('R12/R18: independent personal gains and original announcer base') do
  p.pong_preferences = {'own_volume'=>40, 'opponent_volume'=>150, 'announcer_volume'=>60, 'auto_return'=>false}
  state = GameRoomPong::Engine.new.snapshot
  state['fx'] = [[2, 'step', 0, 15, 0], [3, 'step', 1, 15, 20]]
  a.update(state, viewer: 0, paused: false)
  near(p.sounds['pong_move'].volume, 0.2)
  near(p.sounds['pong_op_move'].volume, 0.3)
  a.start_match
  near(p.sounds['pong_gamestart'].volume, 0.3)
end
a.close
abort(failures.join("\n")) unless failures.empty?
