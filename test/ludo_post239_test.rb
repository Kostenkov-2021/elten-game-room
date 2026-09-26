# encoding: UTF-8
require_relative "support/new_board_games"
require_relative "../lib/game_room_localization"
game = GameRoomGames::Ludo.new
repository = NewGamesRepository.new(%w[Alice Bob Carol Dave])
defaults = game.default_options
exit_options = game.option_definitions.select { |option| %w[enter_on_six enter_on_one].include?(option.key) }
assert(exit_options.map(&:label) == ["A 6 allows leaving the base", "A 1 allows leaving the base"], "Exit checkboxes have unclear labels or the wrong order")
catalog = GameRoomLocalization::Catalog.new(File.binread(File.expand_path('../locale/PL.mo', __dir__)))
assert(exit_options.map { |option| catalog.translate(option.label) } == ["Szóstka pozwala wyjść z bazy", "Jedynka pozwala wyjść z bazy"], "Exit checkboxes did not receive the requested Polish names")
assert(defaults["enter_on_one"] == true, "New tables do not default to exit on one")
[{}, {"enter_on_one" => false}, {"enter_on_one" => true}, {"enter_on_six" => false, "enter_on_one" => false}].each do |options|
  session = {"options" => JSON.generate(options)}
  [1, 2, 6].each do |roll|
    events = [{"id" => 1, "actor" => "Alice", "action" => "roll", "value" => roll.to_s}]
    replay = game.replay(session, events, repository)
    legal = roll == 6 || options["enter_on_six"] == false || (roll == 1 && options["enter_on_one"] == true)
    assert((replay.state[:phase] == :moving) == legal, "Wrong exit rule #{options}/#{roll}")
    next unless legal
    actions = game.legal_actions(replay, "Alice")
    assert(actions.size == 4, "Base choices were lost")
    after = append_surface_action(game, session, repository, events, replay, "Alice", actions.first)
    assert(after.state[:pawns][0][0] == 0, "Exiting also advanced along the track")
    assert(after.current_player == (roll == 6 ? "Alice" : "Bob"), "A one granted another turn")
  end
end
session = {"options" => JSON.generate(defaults)}
replay = game.replay(session, [], repository)
replay.state[:pawns] = [[4, 2, -1, 57], [0, -1, -1, -1], [-1] * 4, [-1] * 4]
history = replay.history.map(&:text)
names = game.send(:all_pawn_browse_choices, replay.state).map(&:label)
assert(names.first(3) == ["Alice, track 3", "Alice, track 5", "Bob, track 14"], "Track order or owner-first labels changed")
game.board_presentation_preferences = {"player_labels" => "colours"}
colours = game.send(:all_pawn_browse_choices, replay.state).map(&:label)
assert(colours.first(3) == ["red, track 3", "red, track 5", "blue, track 14"], "Colour-to-seat mapping changed")
assert(colours.size == 16, "Overlapping/base entries were removed")
shortcuts = game.game_shortcuts(replay, "Bob")
assert(shortcuts.find { |key| key.key == "1" }.message.start_with?("blue:"), "Digit one stopped describing the viewer")
assert(shortcuts.find { |key| key.key == "c" && key.modifiers.empty? }.message.include?("Alice, red; Bob, blue"), "Colour map lost names")
assert(shortcuts.find { |key| key.key == "c" && key.modifiers == [:control] }.action_name == "toggle_player_labels", "Ctrl+C missing")
assert(replay.history.map(&:text) == history, "Presentation rewrote history")
assert(game.send(:all_pawn_browse_choices, replay.state).map(&:label) == colours, "View is unstable")
assert(game.game_shortcuts(replay, "Observer").find { |key| key.key == "1" }.message.start_with?("red:"), "Observer's first seat changed")
puts "PASS Ludo exit rules, legacy replay, concise labels, stable colours, digits and observers"
