require_relative "../../support/new_games_fixture"

game = GameRoomGames::Battleship.new
players = %w[Alice Bob]
repo = NewGames116Repository.new(players)
session = {"__id" => 7, "__players" => players, "options" => JSON.generate(game.default_options)}
before = game.replay(session, [], repo)
assert(game.turn_transition_history_entry(before, before, event_id: 1) == nil, "idle setup announced a turn")
events = players.each_with_index.map { |actor, index| {"id" => index + 1, "actor" => actor, "action" => "place", "value" => "a" * 64} }
partial = game.replay(session, events.take(1), repo)
assert(game.turn_transition_history_entry(before, partial, event_id: 1) == nil, "only one fleet started the game")
ready = game.replay(session, events, repo)
assert(ready.state[:phase] == :playing && ready.current_player == before.current_player, "wrong fixture")
entry = game.turn_transition_history_entry(partial, ready, event_id: 2)
assert(entry && entry.kind == :turn && entry.actor == "Alice", "setup to play lost the first turn")
assert(game.turn_announcement(ready, "Alice") == "It is your turn.", "wrong first-player announcement")
assert(game.turn_announcement(ready, "Bob") == "It is Alice's turn.", "wrong opponent announcement")
assert(game.turn_transition_history_entry(ready, ready, event_id: 2) == nil, "refresh repeated the first turn")
puts "PASS Battleship: first shooting turn is announced exactly at the setup boundary"
