require_relative "../../../lib/audio_ball/engine"

def assert(value, message); raise message unless value; end
assert(GameRoomAudioBall::Engine.instance_method(:step).parameters.include?([:key, :defenses]),
  'physics has no same-frame defense input and awards a goal before checking the key')
[0, 1].product([1, 2, 3, 4, 5], %w[up left down]).each do |receiver, level, shot|
  engine = GameRoomAudioBall::Engine.new(level: level, server: 1 - receiver)
  engine.press(1 - receiver, 'prepare'); engine.press(1 - receiver, shot)
  duration = engine.duration
  engine.step(duration * 0.90, controlled: [receiver], defenses: {receiver => shot})
  assert(engine.phase == :flying, 'held matching key enlarged the two-step defense range')
  engine.step(duration * 0.11, controlled: [receiver], defenses: {receiver => shot})
  assert(engine.phase == :waiting && engine.holder == receiver && engine.goal == nil,
    'held key lost when one physics step crossed the end of the defense window')
  assert(engine.turn == 3, 'held defense produced more than one transition')
end
[{}, {0 => 'down'}, {1 => 'up'}].each do |defenses|
  engine = GameRoomAudioBall::Engine.new(server: 1)
  engine.press(1, 'prepare'); engine.press(1, 'up')
  engine.step(engine.duration, controlled: [0], defenses: defenses)
  assert(engine.goal == 1, 'missing, mismatched or foreign defense caught the ball')
end
engine = GameRoomAudioBall::Engine.new(server: 1)
engine.press(1, 'prepare'); engine.press(1, 'up')
engine.step(engine.duration, controlled: [], defenses: {0 => 'up'})
assert(engine.phase == :flying && engine.goal == nil, 'non-controller decided the remote defense')
puts 'PASS Audio Ball continuous defense: both sides, all difficulties/types, exact two-step range and local authority'
