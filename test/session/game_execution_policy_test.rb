require_relative "../../lib/game_execution_policy"
require_relative "../../games/tic_tac_toe"

def _(text); text; end
def assert(value, message); raise message unless value; end
game = GameRoomGames::TicTacToe.new
repository = GameRoomSimulation::Repository.new(%w[Alice Bob])
replay = game.replay({}, [], repository)
transport = Object.new
transport.define_singleton_method(:set_seat_controller) { |*| raise 'policy performed I/O' }
args = {game: game, replay: replay, session: {}, players: ['Alice', 'Bob', 'bot:1:1'],
  members: ['Alice'], owner: 'Alice', viewer: 'alice', transport: transport}
decision = ->(**changes) { GameRoomExecutionPolicy.departed_players(**args.merge(changes)) }
assert(decision.call == ['Bob'], 'missing participant not selected or named bot selected')
assert(decision.call(members: %w[Alice Bob]) == [], 'present member selected')
assert(decision.call(viewer: 'Bob') == [], 'guest permitted replacement')
assert(decision.call(owner: 'Carol', viewer: 'Carol') == ['Bob'], 'observing owner cannot replace departed player')
assert(decision.call(members: nil) == [], 'unknown membership treated as departure')
assert(decision.call(transport: Object.new) == [], 'unsupported transport accepted')
%w[__frozen __aborted].each { |flag| assert(decision.call(session: {flag => true}) == [], flag) }
assert(decision.call(session: {'__control_ready' => false}) == [], 'unreconciled controller accepted')
assert(decision.call(session: {'__controllers' => {'Bob' => 'bot'}}) == [], 'legacy controller replaced twice')
finished = replay.dup
finished.winner = 'Alice'
assert(decision.call(replay: finished) == [], 'finished game changed seats')
game.define_singleton_method(:controller_change_error) { |*_, **_| :private_phase }
assert(decision.call == [], 'private phase restriction ignored')
repository.define_singleton_method(:session_id) { |s| s.fetch('__id') }
replay.accepted_events = [{'id' => 11}, {'id' => 19}]
assert(GameRoomExecutionPolicy.bot_seed(repository, {'__id' => 7}, replay) == 7 * 1_000_003 + 19 * 97 + 2,
  'refactoring changed deterministic bot seed')
puts 'Shared execution decisions preserve authority, presence, frozen/private phases and bot seed'
