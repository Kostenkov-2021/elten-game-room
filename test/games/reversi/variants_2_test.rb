require_relative "../../support/new_games_fixture"
require_relative "../../../games/reversi"
require_relative "../../../lib/game_simulation"

game = GameRoomGames::Reversi.new
repo = NewGames116Repository.new(%w[Alice Bob])
assert(game.default_options.values_at("allow_passing", "mandatory_capture") == [true, true], "new defaults")
legacy = game.replay({ "options" => "{}" }, [], repo)
assert(game.legal_actions(legacy, "Alice").none? { |a| a["action"] == "pass" }, "old save changed")
positions = []
[false, true].product([false, true]).each do |passing, capture|
  options = { "allow_passing" => passing, "mandatory_capture" => capture }
  session = { "options" => JSON.generate(options) }
  events = []
  replay = game.replay(session, events, repo)
  positions << game.bot_search_key(replay, "Alice")
  placements = game.legal_actions(replay, "Alice").reject { |a| a["action"] == "pass" }
  assert(placements.length == (capture ? 4 : 12), "variant legal moves")
  assert(game.action_for({ "kind" => "grid", "action" => "select", "x" => 0, "y" => 0 }, replay, "Alice").first != :ok, "isolated field")
  if passing
    20.times do
      old = replay
      replay = append_action(game, session, repo, events, replay, replay.current_player, { "kind" => "command", "action" => "pass" })
      assert(!replay.finished? && replay.board == old.board && replay.current_player != old.current_player, "voluntary pass ends game")
      incremental = game.incremental_replay(old, session, [events.last], repo)
      assert(incremental.state == replay.state, "incremental pass diverges")
    end
    assert(game.custom_game_shortcuts(replay, "Alice").any? { |s| s.key == "p" }, "missing P")
    assert(game.custom_game_shortcuts(replay, "Bob").empty?, "P for opponent")
  else
    assert(game.action_for({ "kind" => "command", "action" => "pass" }, replay, "Alice").first != :ok, "forbidden voluntary pass")
  end
  no_capture = { "kind" => "grid", "action" => "select", "x" => 2, "y" => 2 }
  assert((game.action_for(no_capture, replay, replay.current_player).first == :ok) == !capture, "diagonal adjacency")
  next_move = placements.first
  replay = append_action(game, session, repo, events, replay, replay.current_player, next_move)
  assert(replay.accepted_events.length == events.length, "accepted move rejected on replay")
end
assert(positions.uniq.length == 4, "variant search-cache collision")

# Zero-capture placements still flip every enclosed line when one exists.
env = GameRoomSimulation::Environment.new_game(game: game, players: %w[Alice Bob], options: { "mandatory_capture" => false })
assert(env.step({ "kind" => "grid", "action" => "select", "x" => 2, "y" => 3 }) == :ok, "capture-free variant lost captures")
assert(env.replay.board[3][3] == 0, "capture optional became flipping optional")
full = env.replay.dup
full.board = Array.new(8) { Array.new(8, 0) }
full.state = full.state.merge(board: full.board, current_player: "Bob")
finished = game.incremental_replay(full, env.session, [{ "id" => 200, "actor" => "Bob", "action" => "pass", "value" => "" }], repo)
assert(finished.finished? && finished.winner == "Alice", "full board not finished")

# A shallow exact search includes pass nodes, preserves the position and stays
# inside the same bounded search budget in every variant.
[false, true].product([false, true]).each do |passing, capture|
  env = GameRoomSimulation::Environment.new_game(game: game, players: %w[Alice Bob], options: { "allow_passing" => passing, "mandatory_capture" => capture })
  before = Marshal.dump(env.replay.state)
  strategy = GameRoomBots::AlphaBetaStrategy.new(max_depth: 3, node_limit: 3000, optimize_transpositions: true)
  action = strategy.choose(actions: env.legal_actions, actor: "Alice", random_source: env.random_source, game: game, replay: env.replay, simulation: env)
  assert(env.legal_actions.include?(action), "illegal search decision")
  assert(strategy.last_stats[:nodes] <= 3000 && Marshal.dump(env.replay.state) == before, "search mutated game or exceeded budget")
end
puts "Reversi four variants, unlimited passes, legacy replay, captures, ending and bounded bot search: OK"
