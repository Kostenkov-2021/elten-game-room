# encoding: UTF-8
require_relative "../../support/axel_pong_mouse"

# Expected values are hand-derived from ap_ball.HandleBall, not another
# implementation of our own formula. No recovered Python is executed.
[[0.10, 15.25], [0.20, 15.51]].each do |speed, expected_x|
  engine = GameRoomPong::Engine.new(level: 2)
  engine.ball.merge!('x' => 15.0, 'y' => 10.0, 'speed' => speed,
    'lateral' => 0.255, 'dx' => 1, 'dy' => 1)
  engine.step([{}, {}])
  assert((engine.ball['x'] - expected_x).abs < 0.000001, 'lateral cap/scaling order differs from original')
end

control = {'move' => 0, 'hit' => false, 'press' => 0}
[[0, 8, 15.0, 16.0], [1, -8, 16.0, 15.0]].each do |key, dx, launch, final|
  backend = PongMouseBackend.new
  mouse = GameRoomPong::MouseControl.new(backend: backend)

  backend.delta = [0, 0, false]
  mouse.sample(active: true)
  backend.delta = [dx, 0, true]
  mouse.sample(active: true)
  engine = GameRoomPong::Engine.new
  input = mouse.step(control.merge('move' => key, 'hit' => mouse.held?, 'press' => mouse.clicks),
    position: 15.0, now_ms: 16)
  engine.step([input, {}])
  assert(engine.ball['x'] == launch && engine.paddles[0] == final,
    'original order must be keyboard movement, click, mouse movement')
  assert(engine.events.map { |e| e[1] }.include?('serve'), 'left click did not serve')
  # The same held button is not another DOWN edge, but can defend at the goal.
  mouse.finish_frame
  backend.delta = [0, 0, true]
  mouse.sample(active: true)
  assert(mouse.clicks == 1 && !mouse.clicked && mouse.held?, 'held left button became repeated clicks')
  engine.ball.merge!('x' => final, 'y' => 0.9, 'dy' => -1, 'speed' => 0.1, 'dx' => 0)
  input = mouse.step(control.merge('hit' => mouse.held?, 'press' => mouse.clicks), position: final, now_ms: 32)
  engine.step([input, {}])
  assert(engine.goal.nil? && engine.ball['dy'] == 1, 'held mouse did not defend at goal line')
  mouse.suspend
  mouse.sample(active: true)
  assert(!mouse.held? && !mouse.clicked && mouse.clicks == 1, 'held mouse clicked after returning from other control')
  backend.delta = [0, 0, false]
  mouse.sample(active: true)
  backend.delta = [0, 0, true]
  mouse.sample(active: true)
  assert(mouse.clicked && mouse.clicks == 2, 'release/repress after focus did not work')
end

[-1, 1].each do |direction|
  edge = direction == 1 ? 29.0 : 1.0
  backend = PongMouseBackend.new
  mouse = GameRoomPong::MouseControl.new(backend: backend)

  backend.delta = [direction * 8, 0, false]
  mouse.sample(active: true)
  engine = GameRoomPong::Engine.new(paddles: [edge, 15.0])
  input = mouse.step(control, position: edge, now_ms: 16)
  3.times { engine.position([input, {}], now_ms: 16) }
  assert(engine.events.count { |e| e[1] == 'edge' } == 1, 'edge cue absent or duplicated by repeated position packet')
  mouse.finish_frame
  mouse.reset_rally
  mouse.sample(active: true)
  fresh = GameRoomPong::Engine.new(paddles: [edge, 15.0])
  input = mouse.step(control, position: edge, now_ms: 32)
  fresh.position([input, {}])
  assert(fresh.events.count { |e| e[1] == 'edge' } == 1, 'rally reset replayed old edge attempts')
end

# Switching mouse off must not resume an old halfway-through key-repeat cycle.
engine = GameRoomPong::Engine.new
engine.position([control.merge('move' => 1), {}])
engine.position([control.merge('paddle' => 16.0, 'pointer_before' => 16.0,
  'pointer_seq' => 1, 'pointer_edges' => 0), {}])
engine.position([control.merge('move' => 1), {}])
assert(engine.paddles[0] == 17, 'mouse toggle retained stale keyboard repeat state')

puts 'PASS deep reference parity: lateral cap, click/keyboard/motion order, held goal defense, focus release, repeated edge packets, rally and keyboard reset'
