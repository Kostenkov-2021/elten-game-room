# encoding: UTF-8
require_relative "support/new_games_fixture"
require_relative "../games/ludo"
require_relative "../games/mexican_train"

failures = []
check = lambda do |name, &block|
  block.call
  puts "PASS #{name}"
rescue StandardError => error
  failures << "#{name}: #{error.message}"
end

check.call("Makao voluntary draw, profiles, pass and penalties") do
  game = GameRoomGames::Makao.new
  %w[simple polish joker].each do |profile|
    assert(game.normalize_options("profile" => profile, "allow_playable_draw" => false)["allow_playable_draw"] == true, "#{profile} must enable drawing")
  end
  assert(game.normalize_options("profile" => "custom")["allow_playable_draw"] == true, "custom default")
  strict = game.normalize_options("profile" => "custom", "allow_playable_draw" => false)
  assert(strict["allow_playable_draw"] == false, "custom opt-out")
  players = %w[Alice Bob]
  repo = NewGames116Repository.new(players)
  build = lambda do |drawn, options = game.default_options|
    game.send(:initial_state, players, options).merge(phase: :playing, current_player: "Alice",
      hands: {"Alice" => %w[7C 9D], "Bob" => %w[6S 8S]},
      discard: ["5C"], declared_suit: "C", declared_rank: "5", draw_pile: [drawn, "6D", "8D", "TD"])
  end
  view = ->(state) { GameRoomGames::Replay.new(players: players, current_player: state[:current_player], state: state) }
  draw = {"id" => 1, "action" => "draw", "actor" => "Alice", "value" => ""}
  state = build.call("8C")
  assert(game.custom_game_shortcuts(view.call(state), "Alice").find { |s| s.key == "space" }.action_name == "draw", "Space must offer the first draw")
  assert(game.action_for({"kind" => "command", "action" => "draw"}, view.call(state), "Alice").first == :ok, "legal action rejects voluntary drawing")
  assert(game.send(:apply_draw, state, draw, "Alice", repo, []), "replay rejects voluntary drawing")
  assert(state[:hands]["Alice"].last == "8C" && state[:current_player] == "Alice", "playable draw must remain available")
  actions = game.legal_actions(view.call(state), "Alice")
  assert(game.custom_game_shortcuts(view.call(state), "Alice").find { |s| s.key == "space" }.action_name == "pass", "second Space must end, not draw again")
  assert(actions.none? { |a| a["action"] == "draw" } && actions.any? { |a| a["action"] == "pass" }, "one draw, then pass")
  assert(game.send(:apply_pass, state, draw.merge("id" => 2, "action" => "pass"), "Alice", repo, []), "cannot end after drawing")
  assert(state[:current_player] == "Bob", "pass did not advance")
  state = build.call("8H")
  assert(game.send(:apply_draw, state, draw, "Alice", repo, []) && state[:current_player] == "Bob", "nonmatching draw must end turn")
  state = build.call("8C", strict)
  assert(!game.send(:apply_draw, state, draw, "Alice", repo, []), "custom restriction ignored")
  state = build.call("8C").merge(draw_penalty: 3, penalty_kind: :draw)
  assert(game.send(:apply_draw, state, draw, "Alice", repo, []) && state[:hands]["Alice"].length == 5 && state[:current_player] == "Bob", "must accept entire penalty")
  state = build.call("8C").merge(skip_penalty: 2)
  assert(!game.send(:apply_draw, state, draw, "Alice", repo, []), "cannot draw around waiting penalty")
  state = build.call("8C")
  best = game.legal_actions(view.call(state), "Alice").max_by { |a| game.bot_action_score(view.call(state), "Alice", a) }
  assert(best["action"] == "play", "bot draws needlessly with a legal play")
end

check.call("Ludo player digits, last roll author and spatial ordering") do
  game = GameRoomGames::Ludo.new
  players = %w[Alice Bob Carol]
  repo = NewGames116Repository.new(players)
  state = game.send(:initial_state, players, game.default_options)
  assert(game.send(:apply_roll!, state, {"id" => 1, "value" => "1"}, "Alice", repo, []), "roll setup")
  replay = GameRoomGames::Replay.new(players: players, current_player: state[:current_player], state: state)
  assert(game.shortcut_feature_data(:last_roll, replay, "Bob")[:message] == "Alice, 1.", "last roll needs actual author")
  shortcuts = game.custom_game_shortcuts(replay, "Bob")
  digits = shortcuts.select { |s| %w[1 2 3 4].include?(s.key) }
  assert(digits.map(&:key) == %w[1 2 3], "player digit shortcuts missing")
  assert(digits[0].message.start_with?("Bob:") && digits[1].message.start_with?("Carol:") && digits[2].message.start_with?("Alice:"), "viewer-relative seating")
  observed = game.custom_game_shortcuts(replay, "Visitor").find { |s| s.key == "1" }
  assert(observed.message.start_with?("Alice:"), "spectator starts from first seat")
  state[:pawns] = [[4, 2, -1, 57], [42, -1, -1, -1], [-1, -1, -1, -1]]
  labels = game.send(:all_pawn_browse_choices, state).map(&:label)
  assert(labels.first(3) == ["Alice, track 3", "Bob, track 4", "Alice, track 5"],
    "sort the shared track across players, without pawn numbers")
  assert(labels.length == 12, "base/home/finished pawns lost")
end

check.call("Yahtzee concise dice and numerical category bonus") do
  game = GameRoomGames::Yahtzee.new
  assert(game.send(:dice_text, {dice: [1, 2, 3, 4, 5]}) == "1, 2, 3, 4, 5.", "D contains redundant prefix")
  label = game.option_definitions.find { |o| o.key == "upper_bonus" }.label
  assert(label == "35-point bonus for Ones through Sixes", "bonus still uses spatial terminology")
end

check.call("Mexican Train announces a required double once, then only changes") do
  game = GameRoomGames::MexicanTrain.new
  state = game.initial_state(%w[Alice Bob], game.default_options).merge(phase: :playing, current_player: "Alice", round: 1,
    hands: {"Alice" => ["120"], "Bob" => ["130"]}, pending: %w[p0 m], series: true,
    trains: {"p0" => {owner: "Alice", end: 6, open: false, chain: []},
      "p1" => {owner: "Bob", end: 3, open: false, chain: []}, "m" => {owner: nil, end: 9, open: true, chain: []}})
  history = []
  game.send(:end_turn, state, 100, 1, history)
  game.send(:end_turn, state, 101, 2, history)
  assert(history.length == 1 && history.first.text.include?("9"), "same double repeated on next turn")
  state[:pending].pop
  game.send(:end_turn, state, 102, 3, history)
  assert(history.length == 2 && history.last.text.include?("6"), "earlier double newly required must be announced")
  assert(game.send(:destination_error, state, state[:current_player], game.hand(state, state[:current_player]).first, "m").include?("6"), "wrong placement must still explain required double")
  replay = GameRoomGames::Replay.new(players: state[:players], current_player: state[:current_player], state: state)
  assert(game.current_turn_shortcut_text(replay, "Alice").include?("6"), "T must retain on-demand reminder")
  state[:pending].clear
  game.send(:end_turn, state, 103, 4, history)
  assert(history.length == 2, "empty obligation announced")
end

abort failures.join("\n") unless failures.empty?
puts "Widget/game feedback: game regressions OK"
