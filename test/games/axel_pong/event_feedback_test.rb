require_relative '../../support/pong_audio'
require_relative '../../../lib/axel_pong/peer_engine'

class EventFeedbackSound < PongSound
  def initialize(name, program)
    super()
    @name, @program = name, program
  end

  def play
    @program.trace << [@program.frame, @name, @frequency / 44100.0, @pan, @volume]
    super
  end
end

class EventFeedbackProgram < PongAudioProgram
  attr_reader :trace
  attr_accessor :frame
  def initialize
    super
    @trace, @frame = [], 0
  end

  def create_sound_from_asset(name, loop:)
    @loops[name] = loop
    @sounds[name] = EventFeedbackSound.new(name, self)
  end
end

def event_feedback_fixture(paused: false, **options)
  program = EventFeedbackProgram.new
  audio = GameRoomPong::Audio.new(program)
  audio.load
  engine = GameRoomPong::PeerEngine.new(side: 0, authority: true, level: 2,
    on_feedback: ->(state) { audio.feedback(state, viewer: 0, paused: paused) }, **options)
  yield program, audio, engine
ensure
  audio&.close
end

failures = []
{
  'wall at collision, not catch-up presentation' => -> {
    event_feedback_fixture do |program, audio, engine|
      engine.ball.merge!('x' => 28.98, 'y' => 10.0, 'dy' => 1, 'dx' => 1, 'speed' => 0.2, 'lateral' => 0.24)
      (1..4).each do |frame|
        program.frame = frame
        engine.step([{}, {}])
      end
      audio.update(engine.snapshot, viewer: 0, paused: false)
      events = program.trace.select { |row| row[1] == 'pong_wall' }
      assert(events.length == 1 && events[0][0] == 1, "wall delayed/repeated: #{events.inspect}")
    end
  },
  'movement at each original frame and position' => -> {
    event_feedback_fixture do |program, audio, engine|
      (1..6).each { |frame| program.frame = frame; engine.step([{'move' => 1}, {}]) }
      audio.update(engine.snapshot, viewer: 0, paused: false)
      program.trace.clear
      (7..10).each { |frame| program.frame = frame; engine.step([{'move' => 1}, {}]) }
      3.times { audio.update(engine.snapshot, viewer: 0, paused: false) }
      steps = program.trace.select { |row| row[1] == 'pong_move' }
      assert(steps.map(&:first) == [7, 10], "steps delayed/repeated: #{steps.inspect}")
      [17, 18].each_with_index do |x, index|
        pitch = 1.3 - (x - 15).abs * 0.6 / 14
        assert((steps[index][2] - pitch).abs < 1e-9, 'step used final rather than event position')
      end
    end
  }
}.each do |name, scenario|
  scenario.call
  puts "PASS #{name}"
rescue RuntimeError => error
  failures << "#{name}: #{error.message}"
end
raise failures.join("\n") unless failures.empty?

# The original plays the impact curve, then applies the usual distance mix
# in UpdateSounds before finishing that same frame, in either perspective.
[0, 1].product([4, 10, 18, 20]).each do |viewer, depth|
  event_feedback_fixture do |program, audio, engine|
    state = engine.snapshot
    y = viewer.zero? ? depth : 20 - depth
    state['b'].merge!('x' => 28.0, 'y' => y, 'dy' => 1)
    state['fx'] = [[1, 'wall', nil, 28.0, y]]
    audio.feedback(state, viewer: viewer, paused: false)
    start = program.trace.find { |row| row[1] == 'pong_wall' }
    impact_level = [0.95 - (depth - 4) * 0.06, 0].max
    assert((start[4] - impact_level).abs < 1e-9, 'initial wall impact curve changed')
    sound = program.sounds['pong_wall']
    assert((sound.volume - (1.0 - depth * 0.04)).abs < 1e-9, 'wall mix waited for next presentation')
    3.times { audio.update(state, viewer: viewer, paused: false) }
    assert(sound.plays == 1, 'wall feedback echoed at frame end')
  end
end
puts 'PASS wall impact and same-frame distance mix, both perspectives'

# Snapshot-only listeners (including observers) cannot invent missing times,
# but must keep the source/pitch of every transmitted step, not the final x.
[0, 1].each do |viewer|
  event_feedback_fixture do |program, audio, engine|
    state = engine.snapshot
    state['p'] = [18.0, 12.0]
    state['fx'] = [[1, 'step', 0, 17.0, 0], [2, 'step', 1, 13.0, 20],
      [3, 'step', 0, 18.0, 0], [4, 'step', 1, 12.0, 20]]
    2.times { audio.update(state, viewer: viewer, paused: false) }
    steps = program.trace.select { |row| %w[pong_move pong_op_move].include?(row[1]) }
    assert(steps.length == 4, 'snapshot steps missing/repeated')
    [17, 13, 18, 12].each_with_index do |x, index|
      assert((steps[index][2] - (1.3 - (x - 15).abs * 0.6 / 14)).abs < 1e-9, 'queued step lost event pitch')
      if index % 2 == viewer
        assert(steps[index][3].zero?, 'own earlier step incorrectly moved to one side')
      end
    end
  end
end
puts 'PASS queued steps preserve individual pitch and local centring'

event_feedback_fixture do |program, _audio, engine|
  engine.move_to(0, 16.9996)
  assert(engine.events.last[3] == engine.snapshot['p'][0], 'event lost existing paddle precision')
  assert((program.sounds['pong_move'].frequency / 44100.0 - (1.3 - 0.6 / 14)).abs < 1e-9,
    'rounding an event prematurely crossed a positional pitch boundary')
end

# A received serve may arrive while the previous frame still said paused.
# Sound movements now, but let the final readiness decision accept/discard
# the contact without losing it or replaying the early movements.
[false, true].each do |still_paused|
  event_feedback_fixture do |program, audio, engine|
    state = engine.snapshot
    state['b']['dy'] = 1
    state['fx'] = [[1, 'serve', 0, 15.0, 0], [2, 'step', 0, 17.0, 0], [3, 'step', 0, 18.0, 0]]
    2.times { audio.feedback(state, viewer: 0, paused: true) }
    assert(program.sounds['pong_move'].plays == 2, 'paused movements delayed or echoed')
    assert(program.sounds['pong_hit'].plays.zero?, 'pending contact played before readiness decision')
    audio.update(state, viewer: 0, paused: still_paused)
    audio.update(state, viewer: 0, paused: false)
    audio.feedback(state, viewer: 0, paused: false)
    assert(program.sounds['pong_hit'].plays == (still_paused ? 0 : 1), 'contact lost, duplicated or replayed on resume')
    assert(program.sounds['pong_move'].plays == 2, 'early movement played twice')
    assert(audio.instance_variable_get(:@early_movement_effects).empty?, 'consumed early steps retained')
    audio.reset
    audio.feedback(state, viewer: 0, paused: false)
    assert(program.sounds['pong_move'].plays == 4, 'new rally inherited old deduplication')
  end
end
event_feedback_fixture(paused: true) do |program, audio, engine|
  300.times do |index|
    engine.move_to(0, index.even? ? 17.0 : 18.0)
    assert(audio.instance_variable_get(:@early_movement_effects).length <= 8, 'paused step tracking grew beyond event window')
  end
  assert(program.sounds['pong_move'].plays == 300, 'paused rapid movements lost or replayed')
  audio.update(engine.snapshot, viewer: 0, paused: true)
  assert(program.sounds['pong_move'].plays == 300, 'frame-end movement replayed')
end
puts 'PASS waiting movement, serve readiness transition, no replay and bounded deduplication'

event_feedback_fixture(bots: [1]) do |program, audio, engine|
  engine.position([{}, {}], now_ms: 64)
  engine.move_to(1, 15.25)
  assert(program.trace.empty?, 'fractional silent bot movement became a step')
  engine.move_to(1, 16.25)
  assert(program.sounds['pong_op_move'].plays == 1, 'bot step waited for presentation')
  assert(engine.events.last[3..4] == [16.25, 20], 'bot step did not carry its source position')
  engine.remote_bot_sound('step', 1, 2.0, 20)
  assert(program.sounds['pong_op_move'].plays == 1, 'owner accepted remote sound for its own bot')
end
puts 'PASS bot fractional silence, immediate actual step and source coordinates'
