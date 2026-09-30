require_relative "../../support/new_games_fixture"
require_relative "../../../games/tysiac"

[2, 3].each do |count|
  game = GameRoomGames::Tysiac.new
  players = %w[Alice Bob Carol].first(count)
  options = game.normalize_options("variant" => count == 2 ? "two_players" : "three_players")
  state = game.send(:initial_state, players, options)
  state.merge!(round: 1, taker: "Bob", contract: 100)
  state[:scores]["Alice"] = 870
  state[:round_points].merge!("Alice" => 30, "Bob" => 50)
  history = []
  game.send(:complete_round, state, 101, history, surrendered: false)
  assert(state[:barrels]["Alice"][:active] && state[:scores]["Alice"] == 880, "barrel rule changed")
  arrivals = history.select { |entry| entry.kind == :barrel }
  assert(arrivals.length == 1 && arrivals.first.text == "Alice is now on the barrel.", "barrel entry not announced")
  replay = GameRoomGames::Replay.new(players: players, state: state, history: history, accepted_events: [])
  shortcut = game.game_shortcuts(replay, "Bob").find { |item| item.key == "s" && item.modifiers.empty? }
  assert(shortcut.message.include?("Alice: 880, on the barrel") && !shortcut.message.include?("Bob: -100, on the barrel"), "S names the wrong barrel player")
  assert(shortcut.message.index("Alice: 880") < shortcut.message.index("Bob: -100"), "barrel marker changed score ordering")
  description = game.describe_event({ "id" => 101, "action" => "play" }, NewGames116Repository.new(players), replay, "Bob")
  assert(description.count("Alice is now on the barrel.") == 1, "arrival omitted/duplicated in spoken event")
  assert(game.history_entries_for_display(replay, "Observer").count { |entry| entry.kind == :barrel } == 1, "observer history lost barrel entry")
  # Being on the barrel for a second deal is not a new arrival.
  history = []
  state[:round] += 1
  game.send(:complete_round, state, 102, history, surrendered: false)
  assert(state[:barrels]["Alice"][:active] && history.none? { |entry| entry.kind == :barrel }, "arrival repeated on next deal")
  state[:taker], state[:contract] = "Alice", 120
  state[:round] += 1
  game.send(:complete_round, state, 103, history, surrendered: false)
  assert(!state[:barrels]["Alice"][:active], "failed contract did not leave barrel")
  assert(!game.send(:scores_text, state, sorted: true).include?("on the barrel"), "stale barrel marker in S")
end

puts "PASS Tysiac barrel: one spoken/history arrival, S marker/order, no repeated arrival, cleared after failure; both variants"
