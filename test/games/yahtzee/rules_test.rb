require_relative '../../support/new_games_fixture'

players = %w[Alice Bob Carol]
repository = NewGames116Repository.new(players)

yahtzee = GameRoomGames::Yahtzee.new
yahtzee_session = { "options" => JSON.generate(yahtzee.default_options) }
yahtzee_events = []
yahtzee_replay = yahtzee.replay(yahtzee_session, yahtzee_events, repository)
roll = yahtzee.legal_actions(yahtzee_replay, "Alice").first
yahtzee_replay = append_action(yahtzee, yahtzee_session, repository, yahtzee_events, yahtzee_replay, "Alice", roll, context_for)
assert(yahtzee_replay.state[:dice] == yahtzee_replay.state[:dice].sort, "Yahtzee dice are not sorted")
assert(yahtzee_replay.state[:turn_rolls] == 1, "Yahtzee did not count the first roll")
yahtzee_surface = yahtzee.surface_spec(yahtzee_replay, "Alice")
assert(yahtzee_surface.header == yahtzee.name && yahtzee_surface.roll_number == 1,
  "Yahtzee does not expose the stable one-field roll surface")
shortcut_signatures = yahtzee.custom_game_shortcuts(yahtzee_replay, "Alice").map do |shortcut|
  [shortcut.key, shortcut.modifiers]
end
1.upto(6) do |value|
  assert(shortcut_signatures.include?([value.to_s, []]) && shortcut_signatures.include?([value.to_s, [:shift]]),
    "Yahtzee is missing die-value shortcut #{value}")
end
assert(shortcut_signatures.include?(["space", []]), "Yahtzee is missing the dice status shortcut")
assert(yahtzee.custom_game_shortcuts(yahtzee_replay, "Alice").all? do |shortcut|
  !shortcut.payload.key?("number")
end, "Yahtzee shortcuts still select dice by position")
score = yahtzee.legal_actions(yahtzee_replay, "Alice").find { |action| action["action"] == "score" }
yahtzee_replay = append_action(yahtzee, yahtzee_session, repository, yahtzee_events, yahtzee_replay, "Alice", score)
assert(yahtzee_replay.current_player == "Bob", "Yahtzee did not advance after scoring")
assert(yahtzee.default_options["yahtzee_bonus"] && yahtzee.default_options["joker_rule"], "Yahtzee bonus and Joker are not independent enabled defaults")

joker_state = yahtzee.send(:initial_state, players,
  yahtzee.normalize_options("yahtzee_bonus" => false, "joker_rule" => true))
joker_state[:dice] = [6, 6, 6, 6, 6]
joker_state[:turn_rolls] = 2
joker_state[:sheets]["Alice"]["yahtzee"] = 50
assert(yahtzee.send(:available_scoring_categories, joker_state, "Alice") == ["sixes"],
  "Yahtzee Joker did not require the matching open upper category")
joker_state[:sheets]["Alice"]["sixes"] = 30
joker_lower = yahtzee.send(:available_scoring_categories, joker_state, "Alice")
assert(joker_lower.include?("full_house") && !joker_lower.include?("ones"),
  "Yahtzee Joker did not move to the lower section after the matching upper category was filled")
assert(yahtzee.send(:score_category, "large_straight", joker_state[:dice], joker_state, "Alice") == 40,
  "Yahtzee Joker did not provide the fixed large-straight score")
joker_history = []
assert(yahtzee.send(:apply_score, joker_state,
  { "id" => 25, "actor" => "Alice", "action" => "score", "value" => "large_straight" },
  "Alice", repository, joker_history), "Yahtzee rejected a legal Joker category")
assert(joker_state[:yahtzee_bonuses]["Alice"].zero?,
  "Yahtzee awarded an additional bonus although that independent option was disabled")

bonus_state = yahtzee.send(:initial_state, players,
  yahtzee.normalize_options("yahtzee_bonus" => true, "joker_rule" => false))
bonus_state[:dice] = [2, 2, 2, 2, 2]
bonus_state[:turn_rolls] = 2
bonus_state[:sheets]["Alice"]["yahtzee"] = 50
bonus_history = []
assert(yahtzee.send(:apply_score, bonus_state,
  { "id" => 26, "actor" => "Alice", "action" => "score", "value" => "chance" },
  "Alice", repository, bonus_history), "Yahtzee rejected a category with Joker disabled")
assert(bonus_state[:yahtzee_bonuses]["Alice"] == 100,
  "Yahtzee did not award the independently enabled additional-Yahtzee bonus")

puts 'PASS yahtzee: rules, legal actions and options'
