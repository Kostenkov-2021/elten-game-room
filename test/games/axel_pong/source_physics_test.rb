require_relative "../../../lib/axel_pong/engine"

failures = []
check = lambda do |name, &body|
  body.call
  puts "PASS #{name}"
rescue StandardError => error
  failures << "#{name}: #{error.message}"
end
def assert(value, message); raise message unless value; end
def near(value, expected); assert((value - expected).abs < 0.000001, "#{value} != #{expected}"); end

check.call('R01: Nightmare speed, both match types') do
  near(GameRoomPong::Engine.new(level: 6).base_speed, 0.323)
  near(GameRoomPong::Engine.new(level: 6, bots: [1]).base_speed, 0.323)
  near(GameRoomPong::Engine.new(level: 5).base_speed, 0.235)
end
check.call('R02: early automatic cap does not narrow the goal-line rescue') do
  [0, 1].each do |side|
    early = GameRoomPong::Engine.new(automatic: true, guest: 1)
    early.ball.merge!('x' => 19.25, 'y' => side.zero? ? 1.25 : 18.75,
      'speed' => 0.1, 'dy' => side.zero? ? -1 : 1)
    early.step([{}, {}])
    assert(early.incoming?(side), 'returned too early outside four units')
    early.ball['y'] = side.zero? ? 0.9 : 19.1
    early.step([{}, {}])
    assert(!early.incoming?(side) && early.goal.nil?, 'late rescue lost')
  end
end
check.call('R03: released movement memory, expiry, and both perspectives') do
  [0, 1].each do |side|
    e = GameRoomPong::Engine.new(automatic: true, guest: 1)
    moving = [{}, {}]; moving[side] = {'move' => 1}
    e.step(moving, now_ms: 1000)
    e.step([{}, {}], now_ms: 1016)
    e.ball.merge!('x' => 15, 'y' => side.zero? ? 1.4 : 18.6, 'dy' => side.zero? ? -1 : 1)
    near(e.release_bonus(side), 0.35)
    e.instance_variable_set(:@now_ms, 1126)
    near(e.release_bonus(side), 0.175)
    e.instance_variable_set(:@now_ms, 1237)
    near(e.release_bonus(side), 0)
    e.instance_variable_set(:@now_ms, 1000)
    near(e.release_bonus(side), 0)
    e.instance_variable_set(:@now_ms, 1126)
    e.ball['y'] = side.zero? ? 1.7 : 18.3
    near(e.release_bonus(side), 0)
    e.ball['dy'] *= -1
    near(e.release_bonus(side), 0)
  end
end
check.call('R07: independent local automatic return') do
  e = GameRoomPong::Engine.new(automatic: [true, false], guest: 1)
  near(e.hit_width(0), 4.6)
  near(e.hit_width(1), 4.5)
  e.automatic_for(0, false); e.automatic_for(1, true)
  near(e.hit_width(0), 4)
  near(e.hit_width(1), 5.1)
end
check.call('R03: release actually saves the near-goal ball, but not after expiry') do
  [0, 1].product([1032, 1300]).each do |side, at|
    e = GameRoomPong::Engine.new(automatic: true, guest: 1)
    input = [{}, {}]; input[side] = {'move' => 1}
    e.step(input, now_ms: 1000)
    e.step([{}, {}], now_ms: 1016)
    offset = side.zero? ? 5.3 : 5.8
    e.ball.merge!('x' => e.paddles[side] + offset, 'y' => side.zero? ? 0.9 : 19.1,
      'dy' => side.zero? ? -1 : 1, 'speed' => 0.1)
    e.step([{}, {}], now_ms: at)
    assert((e.goal.nil? && !e.incoming?(side)) == (at == 1032), 'released-motion defense/expiry differs')
  end
end
check.call('R28: fractional bot sound step survives the accepted point') do
  first = GameRoomPong::Engine.new(bots: [1])
  first.position([{}, {}], now_ms: 1000)
  first.move_to(1, 16.6)
  assert(first.events.count { |fx| fx[1] == 'step' } == 1, 'fixture step')
  next_round = GameRoomPong::Engine.new(bots: [1], rally: 1, paddles: first.paddles,
    movement_feedback: first.movement_feedback)
  next_round.position([{}, {}], now_ms: 1040)
  next_round.move_to(1, 17.1)
  assert(next_round.events.empty?, 'minimum audible interval lost')
  next_round.position([{}, {}], now_ms: 1050)
  next_round.move_to(1, 17.2)
  assert(next_round.events.count { |fx| fx[1] == 'step' } == 1, 'fractional distance lost')
end
abort(failures.join("\n")) unless failures.empty?
