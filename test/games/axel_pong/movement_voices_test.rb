require_relative "../../../lib/axel_pong/audio"

def assert(value, message); raise message unless value; end
def near(actual, expected, message); assert((actual - expected).abs < 0.000001, message); end

class MovementVoiceSound
  attr_accessor :frequency, :volume, :pan, :position
  attr_reader :plays, :closed
  def initialize
    @frequency, @volume, @pan, @position, @plays = 48000, 0, 0, 0, 0
  end
  def play; @playing = true; @plays += 1; end
  def pause; @playing = false; end
  def playing?; @playing; end
  def finished?; !playing?; end
  def length; 2.0; end
  def close; pause; @closed = true; end
end

class MovementVoiceProgram
  attr_reader :instances, :managed, :released, :pong_preferences
  attr_accessor :in_frame, :muted
  def initialize
    @instances = Hash.new { |h, key| h[key] = [] }
    @managed, @released = [], []
    @pong_preferences = GameRoomPong::Preferences::DEFAULTS.dup
  end
  def create_sound_from_asset(asset, loop:)
    raise 'created a new sound during a live audio frame' if @in_frame
    sound = MovementVoiceSound.new
    @instances[asset] << sound
    sound
  end
  def manage(sound); @managed << sound; end
  def release(sound); @released << sound; end
  def game_room_sound_enabled?(_asset); !@muted; end
  def game_room_sound_volume(_asset); 1.0; end
end

[0, 0, 1, 1].permutation.to_a.uniq.each do |teams|
  teams.each_index do |viewer|
    program = MovementVoiceProgram.new
    audio = GameRoomPong::Audio.new(program, clock: -> { 0.0 }, rng: Random.new(17))
    begin
      audio.load
      audio.prepare_players(4) if audio.respond_to?(:prepare_players)
      %w[pong_move pong_op_move pong_move_double pong_edge pong_op_edge pong_hit pong_op_hit].each do |asset|
        assert(program.instances[asset].length == 4, "#{asset} needs a separate voice for each participant")
      end
      created = program.managed.length
      3.times { audio.prepare_players(4) }
      assert(program.managed.length == created, 'repeated setup leaked sound handles')
      state = {'teams' => teams, 'p' => [4.0, 10.0, 19.0, 25.0],
        'b' => {'x' => 15.0, 'y' => 5.0, 'dy' => 1.0}, 'invisible' => false,
        'fx' => teams.each_index.map { |seat| [seat + 1, 'step', seat, 15, 10] }}
      program.in_frame = true
      audio.update(state, viewer: viewer, paused: false)
      steps = teams.each_index.map do |seat|
        friendly = teams[seat] == teams[viewer]
        asset = teams.take(seat).include?(teams[seat]) ? (friendly ? 'pong_move' : 'pong_op_move') : 'pong_move_double'
        voice = program.instances[asset][seat]
        assert(voice.playing? && voice.plays == 1, "participant #{seat} was overwritten")
        sample_gain = asset == 'pong_move_double' ? 0.7079457843841379 : 1.0
        near(voice.volume, (friendly ? 0.5 : 0.2) * sample_gain, 'movement baseline or sample trim changed')
        near(voice.frequency, 48000 * (1.3 - (state['p'][seat].to_i - 15).abs * 0.6 / 14),
          'footsteps should use positional pitch without the contact identity shift')
        voice.position = 0.25
        voice
      end
      assert(steps.map(&:object_id).uniq.length == 4, 'participants share a playing handle')
      source = (viewer + 1) % 4
      state['fx'] = [[5, 'step', source, 15, 10]]
      audio.update(state, viewer: viewer, paused: false)
      steps.each_with_index do |voice, seat|
        assert(voice.plays == (seat == source ? 2 : 1), 'one step restarted another player')
        near(voice.position, seat == source ? 0 : 0.25, 'one step rewound another player')
      end
      state['fx'] = []
      state['p'].reverse!
      program.pong_preferences.merge!('own_volume' => 40, 'opponent_volume' => 150)
      audio.update(state, viewer: viewer, paused: false)
      audio.tick
      steps.each_with_index do |voice, seat|
        sample_gain = teams.take(seat).include?(teams[seat]) ? 1.0 : 0.7079457843841379
        near(voice.volume, (teams[seat] == teams[viewer] ? 0.2 : 0.3) * sample_gain, 'voice lost its volume group or sample trim')
        delta = state['p'][seat] - state['p'][viewer]
        assert(delta.zero? ? voice.pan.zero? : voice.pan * delta > 0, 'ringing voice followed another participant')
        assert(voice.plays == (seat == source ? 2 : 1), 'position/gain update replayed a step')
      end
      state['fx'] = teams.each_index.map { |seat| [seat + 6, 'edge', seat, 15, 10] }
      audio.update(state, viewer: viewer, paused: true)
      edges = teams.each_index.map do |seat|
        voice = program.instances[seat == viewer ? 'pong_edge' : 'pong_op_edge'][seat]
        assert(voice.playing? && voice.plays == 1, 'simultaneous edge cue was overwritten')
        voice
      end
      assert(edges.map(&:object_id).uniq.length == 4, 'edge cues share a handle')
      %w[serve hit].each_with_index do |kind, batch|
        state['fx'] = teams.each_index.map { |seat| [seat + 10 + batch * 4, kind, seat, 15, 10] }
        audio.update(state, viewer: viewer, paused: false)
        impacts = teams.each_index.map do |seat|
          voice = program.instances[seat == viewer ? 'pong_hit' : 'pong_op_hit'][seat]
          assert(voice.playing? && voice.plays == batch + 1, 'another player interrupted a serve/hit')
          expected_pitch = teams.take(seat).include?(teams[seat]) ? 1.0 : 2.0**(-4.0 / 12)
          near(voice.frequency, 48000 * expected_pitch, 'impact identity changed with the listener or action')
          voice
        end
        assert(impacts.map(&:object_id).uniq.length == 4, 'impacts share a handle')
      end
      program.muted = true
      audio.tick
      assert(program.managed.none?(&:playing?), 'mute left a pooled voice playing')
      audio.reset
      assert(program.managed.length == created, 'reset created more movement voices')
      audio.close
      assert(program.managed.all?(&:closed), 'close leaked a voice')
      assert(program.released.length == created && program.released.uniq.length == created, 'a voice was released twice or not released')
    ensure
      audio.close
    end
  end
end

program = MovementVoiceProgram.new
audio = GameRoomPong::Audio.new(program)
begin
  audio.load
  audio.prepare_players(2) if audio.respond_to?(:prepare_players)
  assert(program.instances.values.all? { |voices| voices.length == 1 }, 'Single allocated extra movement voices')
ensure
  audio.close
end
puts 'PASS independent Pong movement/edge/hit voices: four simultaneous sources, distinct footsteps and four-semitone contacts, no rewinds, stable resources, volume/mute/reset/close; Single uses its original handles'
