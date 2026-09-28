require_relative 'support/ui'
require_relative 'support/log'
class Program
  def self.server_app(**_options); end
end
require_relative '../__app'
require_relative '../lib/axel_pong/bot'
require_relative '../lib/realtime/protocol'

def assert(value, message); raise message unless value; end

engine_type = GameRoomPong::Engine
6.times do |i|
  game = engine_type.new(level: i + 1, rng: Random.new(101))
  assert(game.base_speed == engine_type::BASE_SPEED[i], 'network difficulty mismatch')
  assert(!game.strike(1), 'wrong player served')
  assert(game.strike(0), 'cannot serve')
  assert(game.ball['dy'] == 1 && game.ball['speed'] == game.base_speed * 1.2, 'serve physics')
  game.ball.merge!('x' => 18.0, 'y' => 16.0)
  assert(game.strike(1), 'opposite receiver cannot return')
  assert(game.ball['dy'] == -1 && game.ball['dx'] == 1, 'return orientation')
  8.times { game.move(1, 1) }
  assert(game.paddles[1] > 15, 'guest right must preserve the original shared X axis')
  game.ball.merge!('x' => 29.2, 'y' => 10.0, 'dx' => 1, 'dy' => 1, 'lateral' => 0.2)
  game.step([{}, {}])
  assert(game.ball['dx'] == -1 && game.ball['lateral'] <= 0.2, 'wall bounce')
end
[0, 1].each do |side|
  game = engine_type.new(level: 6, automatic: false)
  game.ball.merge!('x' => 1.0, 'y' => side.zero? ? 0.0 : 20.0, 'dy' => side.zero? ? -1 : 1, 'speed' => 2.0)
  game.step([{}, {}])
  assert(game.goal == 1 - side, 'wrong scorer')
  bytes = Marshal.dump(game.snapshot)
  20.times { game.step([{}, {}]) }
  assert(bytes == Marshal.dump(game.snapshot), 'point was not frozen')
end
8.times do |rally|
  assert(engine_type.new(rally: rally).server == (rally / 2) % 2, 'serve rotation')
end
game = engine_type.new(arcade: true, automatic: false)
game.shields[0] = 625
game.ball.merge!('x' => 2.0, 'y' => 0.0, 'dy' => -1, 'speed' => 0.1)
game.instance_variable_set(:@invisible, true)
game.step([{}, {}])
assert(game.goal == nil && game.ball['dy'] == 1 && game.invisible, 'shield must not reveal invisible ball')
assert(game.shields[0] == 624, 'shield timer')

game = engine_type.new(bots: [1])
game.ball.merge!('x' => 1.0, 'y' => 8.0, 'dy' => 1, 'speed' => 0.01)
game.instance_variable_set(:@invisible, true)
bot = GameRoomPong::Bot.new(1, level: 2, rng: Random.new(3))
100.times { bot.step(game); game.step([{}, {}]) }
assert(game.paddles[1] == 15, 'bot tracked invisible ball')

repo = Object.new
def repo.players_for(s); s['__players']; end
def repo.actor_of(e, _s); e['actor']; end
def repo.event_id(e); e['__id']; end
rules = GameRoomGames::AxelPong.new
session = {'__players' => ['Alice', 'Bob'], 'player_one' => 'Owner', 'options' => JSON.generate(rules.default_options)}
events = []
[0, 1].cycle.take(20).each_with_index do |winner, i|
  events << {'__id' => i + 1, 'action' => 'pong_point', 'value' => "#{i}:#{winner}", 'actor' => 'Owner'}
end
replay = rules.replay(session, events, repo)
assert(replay.state[:scores] == [10, 10] && !replay.finished?, 'deuce')
events << {'__id' => 21, 'action' => 'pong_point', 'value' => '20:0', 'actor' => 'Owner'}
assert(!rules.replay(session, events, repo).finished?, 'one point lead won')
events << {'__id' => 22, 'action' => 'pong_point', 'value' => '21:0', 'actor' => 'Owner'}
events << events.last.dup
replay = rules.replay(session, events, repo)
assert(replay.winner == 'Alice' && replay.state[:scores] == [12, 10], 'deuce winner/dedup')
replay = rules.replay(session, events.map { |e| e.merge('actor' => 'Bob') }, repo)
assert(replay.state[:scores] == [0, 0], 'unauthorized scores')
assert(!rules.supports_saved_games? && !rules.supports_bot_move_delay?, 'unsafe save/bot delay')
assert(rules.default_options.keys.sort == %w[arcade custom_target difficulty p2p_enabled p2p_participants_limit target team_size], 'wrong settings: personal automatic return must not be a table rule')

started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
steps = 0
6.times do |level|
  engine = engine_type.new(level: level + 1, bots: [0, 1], arcade: true, rng: Random.new(level))
  bots = [0, 1].map { |side| GameRoomPong::Bot.new(side, level: level + 1, rng: Random.new(level + side)) }
  2000.times do
    break if engine.goal
    bots.each { |b| b.step(engine) }; engine.step([{}, {}]); steps += 1
    payload = GameRoomRealtime::Protocol.encode(match: 'm' * 24, epoch: 'e' * 16, sequence: 99,
      kind: 'state', body: {'r' => 99, 'paused' => false, 'state' => engine.snapshot})
    assert(payload.bytesize <= 1100, 'oversized snapshot')
  end
end
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
puts "PASS Pong rules, physics, bots, payload size; #{steps} steps in #{elapsed.round(3)}s (not a live latency test)"
