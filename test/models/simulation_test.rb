require_relative "../../tools/training/match_runner"
def _(text)
  text
end

require_relative "../../lib/game_simulation"
require_relative "../../games/tic_tac_toe"
require_relative "../../games/four_in_a_row"
require_relative "../../games/farkle"
require_relative "../../games/ninety_nine"
require_relative "../../games/spades"

def assert(condition, message)
  raise message if !condition
end

bots = GameRoomParticipants.bots_for(1, 2)
first = GameRoomSimulation::MatchRunner.new(
  game: GameRoomGames::TicTacToe.new,
  players: bots
).run(seed: 81)
second = GameRoomSimulation::MatchRunner.new(
  game: GameRoomGames::TicTacToe.new,
  players: bots
).run(seed: 81)
assert(first.finished?, "a headless tic-tac-toe match did not finish")
assert(first.events == second.events, "the same simulation seed produced a different match")
assert(first.rewards.values.sum == 0.0, "a two-player result is not zero-sum")

environment = GameRoomSimulation::Environment.new_game(
  game: GameRoomGames::FourInARow.new,
  players: bots,
  seed: 12
)
original_replay = environment.replay
branch = environment.fork
assert(branch.replay.equal?(original_replay), "a shareable board snapshot was copied before the branch changed")
action = branch.legal_actions.first
assert(branch.step(action, actor: branch.active_actor) == :ok, "a legal action was rejected in a branch")
assert(environment.events.empty?, "searching a branch changed the original game")
assert(branch.events.length == 1, "a branch did not retain its own action")
assert(environment.replay.board.flatten.compact.empty?, "a search branch changed the original board")
assert(!branch.replay.equal?(original_replay), "a changed branch kept using the parent replay")
rebuilt_branch = environment.game.replay(
  branch.session,
  branch.events,
  branch.repository
)
assert(branch.replay.board == rebuilt_branch.board, "the incremental Four in a Row board differs from a full replay")
assert(branch.replay.current_player == rebuilt_branch.current_player,
  "the incremental Four in a Row turn differs from a full replay")
assert(branch.replay.accepted_events == rebuilt_branch.accepted_events,
  "the incremental Four in a Row event list differs from a full replay")

tactical_events = [
  { "id" => 1, "actor" => bots[0], "action" => "place", "value" => "1,1" },
  { "id" => 2, "actor" => bots[1], "action" => "place", "value" => "2,1" },
  { "id" => 3, "actor" => bots[0], "action" => "place", "value" => "1,2" },
  { "id" => 4, "actor" => bots[1], "action" => "place", "value" => "2,2" }
]
tactical = GameRoomSimulation::Environment.from_snapshot(
  game: GameRoomGames::TicTacToe.new,
  session: { "__id" => 1, "table_id" => 1, "options" => "{}" },
  events: tactical_events,
  players: bots,
  seed: 4
)
tactical_move = tactical.game.bot_strategy.choose(
  actions: tactical.legal_actions,
  observation: tactical.observation(tactical.active_actor),
  actor: tactical.active_actor,
  random_source: tactical.random_source,
  game: tactical.game,
  replay: tactical.replay,
  context: tactical.context,
  simulation: tactical
)
assert(tactical_move["x"] == 0 && tactical_move["y"] == 2, "MCTS missed an immediate winning move")

server_event_environment = GameRoomSimulation::Environment.from_snapshot(
  game: GameRoomGames::TicTacToe.new,
  session: { "__id" => 7, "table_id" => 3, "options" => "{}" },
  events: [
    { "__id" => 41, "actor" => bots[0], "action" => "place", "value" => "1,1" }
  ],
  players: bots,
  seed: 4
)
assert(
  server_event_environment.replay.accepted_events.length == 1,
  "the simulation rejected an event using the server-side __id field"
)
assert(
  server_event_environment.step(server_event_environment.legal_actions.first) == :ok,
  "a bot could not continue a session loaded from real server rows"
)

farkle = GameRoomSimulation::MatchRunner.new(
  game: GameRoomGames::Farkle.new,
  players: bots,
  options: { "score_limit" => 200, "turn_minimum" => 20, "entry_minimum" => 20 },
  max_actions: 2_000
).run(seed: 9)
assert(farkle.finished?, "the Farkle simulation did not finish")

ninety_nine_game = GameRoomGames::NinetyNine.new
ninety_nine = GameRoomSimulation::MatchRunner.new(
  game: ninety_nine_game,
  players: bots,
  options: { "starting_tokens" => 1 },
  max_actions: 3_000
).run(seed: 9)
assert(ninety_nine.finished?, "the Ninety-nine simulation did not finish")
ninety_environment = GameRoomSimulation::Environment.new_game(
  game: ninety_nine_game,
  players: bots,
  options: { "starting_tokens" => 1 },
  seed: 9
)
observation = ninety_environment.observation(bots.first)
assert(observation.key?("hand"), "a card bot cannot see its own hand")
assert(!observation.key?("hands"), "a Ninety-nine observation exposes every private hand")
assert(!ninety_nine_game.perfect_information?, "Ninety-nine incorrectly enables perfect-information search")

spades_game = GameRoomGames::Spades.new
spades_players = GameRoomParticipants.bots_for(1, 3)
spades = GameRoomSimulation::MatchRunner.new(
  game: spades_game,
  players: spades_players,
  options: { "score_limit" => 30, "team_size" => 0 },
  max_actions: 3_000
).run(seed: 9)
assert(spades.finished?, "the Spades simulation did not finish")
spades_environment = GameRoomSimulation::Environment.new_game(
  game: spades_game,
  players: spades_players,
  options: { "score_limit" => 30, "team_size" => 0 },
  seed: 9
)
spades_observation = spades_environment.observation(spades_players.first)
assert(!spades_observation.key?("hands"), "a Spades observation exposes every private hand")
assert(!spades_game.perfect_information?, "Spades incorrectly enables perfect-information search")

# Spades extends the cached simulation replay instead of rebuilding an
# ever-growing event stream after every card. Compare it with the production
# replay through a complete round so the fast path cannot drift from the
# server-side source of truth.
incremental_environment = GameRoomSimulation::Environment.new_game(
  game: spades_game,
  players: spades_players,
  options: { "score_limit" => 300, "team_size" => 0, "quicksand" => true },
  seed: 91
)
cached_replay_id = incremental_environment.replay.object_id
60.times do
  break if incremental_environment.finished?

  actor = incremental_environment.active_actor
  action = incremental_environment.legal_actions(actor).first
  assert(incremental_environment.step(action, actor: actor) == :ok,
    "the incremental Spades replay rejected a legal action")
  assert(incremental_environment.replay.object_id == cached_replay_id,
    "the Spades simulator rebuilt its replay instead of extending it")
  rebuilt = spades_game.replay(
    incremental_environment.session,
    incremental_environment.events,
    incremental_environment.repository
  )
  assert(incremental_environment.replay.state == rebuilt.state,
    "the incremental Spades state differs from a full production replay")
  assert(incremental_environment.replay.accepted_events == rebuilt.accepted_events,
    "the incremental Spades replay accepted a different event stream")
  assert(incremental_environment.replay.history == rebuilt.history,
    "the incremental Spades history differs from a full production replay")
end

team_players = GameRoomParticipants.bots_for(1, 4)
team_replay = GameRoomGames::Replay.new(
  players: team_players,
  current_player: nil,
  winner: "team:0",
  draw: false,
  accepted_events: [],
  state: {
    options: spades_game.normalize_options("team_size" => 2),
    winner: "team:0"
  }
)
assert(spades_game.bot_reward(team_replay, team_players[0]) == 1.0, "a winning Spades teammate was penalized")
assert(spades_game.bot_reward(team_replay, team_players[1]) == -1.0, "a losing Spades team was rewarded")
assert(spades_game.bot_allied?(team_replay, team_players[0], team_players[2]), "Spades teammates are not allied in search")

puts "Headless game simulation tests passed"
