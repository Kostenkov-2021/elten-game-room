require_relative "../../support/pong_audio"
require_relative "../../../lib/axel_pong/bot"

# Original default gain: own cue 50%, far opponent 20%. Highest pitch at
# the centre, regardless of which end of the court the listener occupies.
[0, 1].each do |viewer|
  program = PongAudioProgram.new
  audio = GameRoomPong::Audio.new(program)
  audio.load
  state = GameRoomPong::Engine.new.snapshot
  number = 0
  [viewer, 1 - viewer].each do |side|
    frequencies = [1, 8, 15, 22, 29].map do |position|
      state['p'][side] = position
      state['fx'] = [[number += 1, 'step', side, position, side * 20]]
      audio.update(state, viewer: viewer, paused: false)
      sound = program.sounds[side == viewer ? 'pong_move' : 'pong_op_move']
      expected_volume = side == viewer ? 0.5 : 0.2
      assert((sound.volume - expected_volume).abs < 0.000001, 'paddle cue does not use the original own/opponent proportions')
      sound.frequency
    end
    expected = [0.7, 1.0, 1.3, 1.0, 0.7].map { |factor| 44100 * factor }
    assert(frequencies.zip(expected).all? { |actual, target| (actual - target).abs < 0.000001 }, 'paddle pitch is not symmetric about the centre')
  end
  program.gain = 0.2
  state['fx'] = [[number += 1, 'step', 1 - viewer, state['p'][1 - viewer], (1 - viewer) * 20]]
  audio.update(state, viewer: viewer, paused: false)
  assert((program.sounds['pong_op_move'].volume - 0.04).abs < 0.000001, 'opponent paddle ignored shared volume')
  state['fx'] = [[number += 1, 'step', viewer, state['p'][viewer], viewer * 20]]
  audio.update(state, viewer: viewer, paused: false)
  assert((program.sounds['pong_move'].volume - 0.1).abs < 0.000001, 'own paddle ignored shared volume')
  audio.close
end

# Slow, continuous bot movement must accumulate into audible steps without
# changing its physical position or generating a cue for every tiny delta.
engine = GameRoomPong::Engine.new(bots: [1])
engine.move_to(1, 15.25)
assert(engine.events.empty?, 'sub-step generated excessive audio')
engine.move_to(1, 15.5)
assert(engine.events.empty?, 'less than a full reference step generated audio')
engine.position([{}, {}], now_ms: 64)
engine.move_to(1, 15.75)
engine.move_to(1, 16.0)
assert(engine.paddles[1] == 16.0 && engine.events.count { |event| event[1] == 'step' } == 1, 'step accumulation changed movement/cue frequency')

# In particular, the normal-level bot takes steps of 0.66 * 0.75 = 0.495
# before serving. Every individual step used to fall below the audio limit.
(1..6).each do |level|
  engine = GameRoomPong::Engine.new(level: level, bots: [1], rally: 2)
  bot = GameRoomPong::Bot.new(1, level: level, rng: Random.new(17))
  moved = sounded = false
  200.times do
    break unless engine.ball['dy'].zero?
    previous = engine.paddles[1]
    bot.step(engine)
    engine.step([{}, {}])
    moved ||= previous != engine.paddles[1]
    sounded ||= engine.events.any? { |event| event[1] == 'step' && event[2] == 1 }
  end
  assert(moved && sounded, "level #{level}: bot moved silently before serving")
end

puts 'PASS Pong paddle feedback: original 50%/20% proportions, symmetric pitch, shared gain, cumulative bot steps, pre-serve movement at all six levels'
