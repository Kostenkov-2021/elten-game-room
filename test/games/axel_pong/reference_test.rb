require_relative "../../../lib/axel_pong/peer_engine"
require_relative "../../../lib/axel_pong/bot"
require_relative "../../../lib/realtime/protocol"

def assert(value, message); raise message unless value; end
def near(actual, expected, message)
  assert((actual - expected).abs < 0.000001, "#{message}: #{actual} != #{expected}")
end
class ReferenceRandom
  def initialize(*values); @values = values; end
  def rand(_limit = nil); @values.shift || 0.5; end
end

# Hand-derived fixtures from the verified ball/input functions. Do not execute
# the original program or use our implementation to calculate expected values.
game = GameRoomPong::Engine.new
positions = 10.times.map { game.step([{'move' => 1}, {}]); game.paddles[0] }
assert(positions == [16, 16, 16, 16, 16, 16, 17, 17, 17, 18], 'reference key repeat')
game = GameRoomPong::Engine.new(level: 2, rng: ReferenceRandom.new(0.25, 0.75))
game.ball.merge!('x' => 17.0, 'y' => 5.0, 'dy' => -1, 'speed' => 0.2)
assert(game.strike(0), 'manual early return')
near(game.ball['speed'], 0.20975, 'forward increment uses first random draw')
near(game.ball['lateral'], 0.146625, 'steer plus second random draw')
game = GameRoomPong::Engine.new(level: 2)
game.ball.merge!('x' => 28.8, 'y' => 5.0, 'speed' => 0.2, 'lateral' => 0.25, 'dx' => 1, 'dy' => 1)
game.step([{}, {}])
near(game.ball['x'], 29.3, 'wall crossing is not clamped')
near(game.ball['lateral'], 0.073875, 'wall attenuation then damping')
assert(game.ball['dx'] == -1, 'wall direction')

[0, 1].each do |side|
  engine = GameRoomPong::PeerEngine.new(side: side, authority: side.zero?, guest: 1)
  engine.ball.merge!('x' => 19.25, 'y' => side.zero? ? 4.0 : 16.0, 'dy' => side.zero? ? -1 : 1, 'speed' => 0.1)
  assert(engine.strike(side) == (side == 1), 'original guest/host reach difference')
end
outgoing = GameRoomPong::PeerEngine.new(side: 0, authority: true)
outgoing.ball.merge!('x' => 14.0, 'y' => 20.1, 'dy' => 1, 'dx' => 1, 'lateral' => 0.1, 'speed' => 0.2)
outgoing.step([{}, {}])
near(outgoing.ball['y'], 20.1, 'far outgoing Y waits for return')
assert(outgoing.ball['x'] > 14 && outgoing.goal == nil, 'invented remote miss or frozen X')

game = GameRoomPong::Engine.new(arcade: true, shields: [500, 600])
game.position([{}, {}], now_ms: 50_000)
game.step([{}, {}], now_ms: 60_000)
assert(game.shields == [500, 600], 'shield expired before serve')
game.strike(0)
game.step([{}, {}], now_ms: 60_016)
assert(game.shields == [499, 599], 'shield did not resume on serve')
game.ball.merge!('x' => 20.0, 'y' => 0.5, 'dy' => -1, 'speed' => 0.1)
game.instance_variable_set(:@invisible, true)
game.step([{}, {}], now_ms: 60_032)
assert(game.ball['dy'] == 1 && game.ball['y'] == 1.0 && game.invisible && game.shields[0] > 0,
  'shield consumed, revealed ball, or bounced from wrong depth')
copy = GameRoomPong::Engine.new(paddles: game.paddles, shields: game.shields, rally: 1)
assert(copy.paddles == game.paddles && copy.shields == game.shields, 'between-point preservation')

bot = GameRoomPong::Bot.new(1, level: 2, rng: ReferenceRandom.new)
game = GameRoomPong::Engine.new(bots: [1])
bot.step(game)
game.ball.merge!('x' => 18.9, 'y' => 20.01, 'dy' => 1, 'speed' => 0.1)
game.step([{}, {}], now_ms: 1000)
assert(game.goal == 0 && game.paddles[1] == 15, 'bot moved before resolving missed contact')
game = GameRoomPong::Engine.new(bots: [1])
bot = GameRoomPong::Bot.new(1, level: 2, rng: ReferenceRandom.new)
bot.step(game)
game.strike(0)
game.ball['x'] = 22
20.times { game.step([{}, {}]) }
assert(game.paddles[1] == 15, 'bot read new serve before reference reaction time')
10.times { game.step([{}, {}]) }
assert(game.paddles[1] > 15, 'bot never reacted to visible serve')
position = game.paddles[1]
game.instance_variable_set(:@invisible, true)
20.times { game.step([{}, {}]) }
assert(game.paddles[1] == position, 'bot tracked invisible ball')

# Reliable transitions are quantized to thousandths; source physics is not.
human = GameRoomPong::PeerEngine.new(side: 0, authority: true, rng: ReferenceRandom.new(0.25, 0.75))
human.ball.merge!('x' => 17.12345, 'y' => 5.0, 'dy' => -1, 'speed' => 0.2)
human.strike(0)
message = human.take_transition
near(message['ball']['x'], 17.123, 'wire X precision')
near(human.ball['x'], 17.12345, 'wire quantization leaked into local flight')
packet = GameRoomRealtime::Protocol.encode(match: 'm' * 24, epoch: 'e' * 16, sequence: 2**31 - 1,
  kind: 'state', body: {'r' => 999999, 'local' => 1, 'turn' => 2**31 - 1, 'goal' => nil,
  'ready' => true, 'paused' => false, 'state' => human.snapshot})
assert(packet.bytesize <= GameRoomRealtime::Protocol::MAX_BYTES, 'new state exceeds channel packet limit')
puts 'PASS reference Pong fixtures: input/physics order, wall/steer RNG, asymmetric reach, far flight, shields, bot visibility/reaction, wire precision'
