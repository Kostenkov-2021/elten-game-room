require_relative "../../support/new_board_games"

players = ["Alice", "Bob"]
repository = NewGamesRepository.new(players)
session = { "options" => "{}" }

checkers = GameRoomGames::Checkers.new
defaults = checkers.default_options
assert(defaults["board_size"] == 8, "Checkers does not default to the classic 64-field board")
assert(defaults["rules"] == GameRoomGames::Checkers::CLASSIC_RULES, "Checkers does not default to the classic rule set")
checkers_start = checkers.replay(session, [], repository)
assert(checkers_start.board.flatten.count { |piece| piece == "0m" } == 12, "Checkers does not give the first player 12 pieces")
assert(checkers_start.board.flatten.count { |piece| piece == "1m" } == 12, "Checkers does not give the second player 12 pieces")
assert(checkers.legal_actions(checkers_start, "Alice").length == 7, "Checkers has an invalid opening move count")
checkers_surface = checkers.surface_spec(checkers_start, "Alice")
assert(checkers_surface.default_coordinate_label_set == "numeric", "Checkers does not default to draughts numbering")
assert(checkers_surface.coordinate_label_sets["numeric"][7][1] == "1", "Checkers numbering does not begin at the upper left playable field")
assert(checkers_surface.coordinate_label_sets["numeric"][0][0] == "29", "Checkers numbering does not end on the lower rows")
assert(checkers_surface.coordinate_label_sets["algebraic"][0][1] == "B1", "Checkers algebraic notation omits a light field")
assert(checkers_surface.coordinate_label_sets["algebraic"][0][0] == "A1", "Checkers algebraic notation omits a playable field")
assert(checkers_surface.navigable_by_coordinate_label_set["numeric"] == nil, "Checkers numeric notation does not expose the physical 64-field board")
assert(checkers_surface.silent_positions_by_coordinate_label_set["numeric"].length == 32, "Checkers numeric notation does not silence all 32 unplayable fields")
assert(checkers_surface.silent_sound == "ding", "Checkers unplayable fields do not use the agreed sound")
checkers_empty_message = checkers_surface.origin_error.call([0, 0], "A1", nil, ->(position) { position.join(",") })
assert(checkers_empty_message == "Field A1 is empty.", "Checkers did not explain an empty field")
checkers_opponent_position = checkers_start.board.each_with_index.lazy.flat_map do |row, y|
  row.each_with_index.filter_map { |piece, x| [x, y] if piece.to_s.start_with?("1") }
end.first
checkers_opponent_piece = checkers_surface.pieces[checkers_opponent_position[1]][checkers_opponent_position[0]]
checkers_opponent_message = checkers_surface.origin_error.call(
  checkers_opponent_position,
  "opponent field",
  checkers_opponent_piece,
  ->(position) { position.join(",") }
)
assert(checkers_opponent_message.include?("belongs to your opponent"), "Checkers did not explain an opponent's piece")
assert(checkers_surface.navigable_by_coordinate_label_set.key?("algebraic") && checkers_surface.navigable_by_coordinate_label_set["algebraic"] == nil, "Checkers algebraic notation does not expose the full board")
assert(checkers_surface.pieces[0][0].label == "white man", "Checkers does not describe a piece by colour and kind")
assert(checkers_surface.default_orientation == "normal", "The first checkers player does not start at the bottom")
assert(checkers.surface_spec(checkers_start, "Bob").default_orientation == "rotated", "The second checkers player does not start at the bottom")
checkers_shortcuts = checkers.game_shortcuts(checkers_start, "Alice")
assert(checkers_shortcuts.any? { |shortcut| shortcut.key == "k" && shortcut.modifiers.empty? && shortcut.kind == :surface }, "Checkers K does not navigate through the player's kings")
assert(checkers_shortcuts.any? { |shortcut| shortcut.key == "k" && shortcut.modifiers == [:shift] && shortcut.kind == :surface }, "Checkers Shift+K does not navigate through opposing kings")
assert(checkers_shortcuts.any? { |shortcut| shortcut.key == "h" && shortcut.modifiers == [:control] }, "Checkers has no notation shortcut")
assert(checkers_shortcuts.any? { |shortcut| shortcut.key == "h" && shortcut.modifiers == [:control, :shift] }, "Checkers has no orientation shortcut")
international_session = { "options" => '{"board_size":10}' }
international = checkers.replay(international_session, [], repository)
international_labels = checkers.surface_spec(international, "Alice").coordinate_label_sets["numeric"]
assert(international_labels[9][1] == "1", "International checkers does not begin with field 1")
assert(international_labels[6][8] == "20", "International checkers does not end the upper setup on field 20")
assert(international_labels[5][1] == "21" && international_labels[4][8] == "30", "International checkers middle fields are not 21 through 30")
assert(international_labels[3][1] == "31" && international_labels[0][8] == "50", "International checkers lower setup is not 31 through 50")
checkers_events = []
checkers_after = append_surface_action(
  checkers, session, repository, checkers_events, checkers_start, "Alice", checkers.legal_actions(checkers_start, "Alice").first
)
assert(
  checkers.describe_event(checkers_events.last, repository, checkers_after, "Bob").to_s.include?("white man from"),
  "Checkers did not expose its move announcement"
)
numeric_history = checkers.history_entries_for_display(
  checkers_after,
  "Alice",
  surface_state: { "coordinate_label_set" => "numeric" }
)
algebraic_history = checkers.history_entries_for_display(
  checkers_after,
  "Alice",
  surface_state: { "coordinate_label_set" => "algebraic" }
)
assert(numeric_history.last.text.include?("from 21 to 17"), "Checkers default history lost draughts field numbering")
assert(algebraic_history.last.text.include?("from A3 to B4"), "Checkers history did not apply the local algebraic-notation filter")
assert(checkers_after.history.last.text.include?("from 21 to 17"), "The local history filter changed the authoritative replay history")
capture_board = Array.new(8) { Array.new(8) }
capture_board[2][0] = "0m"
capture_board[2][4] = "0m"
capture_board[3][1] = "1m"
capture_state = checkers_start.state.merge(board: capture_board, current_player: "Alice", forced_from: nil)
capture_replay = GameRoomGames::Replay.new(
  board: capture_board,
  players: checkers_start.players,
  current_player: "Alice",
  winner: nil,
  draw: false,
  accepted_events: [],
  history: checkers_start.history,
  state: capture_state
)
capture_actions = checkers.legal_actions(capture_replay, "Alice")
assert(capture_actions.length == 1, "Mandatory capture did not suppress ordinary checkers moves")
assert(capture_actions.first["to_x"] == 2 && capture_actions.first["to_y"] == 4, "Checkers generated the wrong capture")
capture_surface = checkers.surface_spec(capture_replay, "Alice")
non_capturing_piece = capture_surface.pieces[2][4]
mandatory_message = capture_surface.origin_error.call(
  [4, 2],
  "unused piece",
  non_capturing_piece,
  ->(position) { position == [0, 2] ? "21" : position.join(",") }
)
assert(
  mandatory_message == "Capturing is mandatory. Choose a piece on 21.",
  "Checkers did not identify mandatory capturing or the selectable piece"
)
sequence_board = Array.new(8) { Array.new(8) }
sequence_board[2][0] = "0m"
sequence_board[3][1] = "1m"
sequence_board[5][3] = "1m"
sequence_state = checkers_start.state.merge(
  board: sequence_board, current_player: "Alice", forced_from: nil, last_to: nil,
  captured_this_turn: false, promoted_this_turn: false
)
first_jump = checkers.send(:moves_for_state, sequence_state, "Alice").first
checkers.send(:apply_move!, sequence_state, first_jump, "Alice")
assert(sequence_state[:forced_from] == [2, 4], "Checkers did not retain the moving piece during a multiple capture")
second_jump = checkers.send(:moves_for_state, sequence_state, "Alice").first
assert(second_jump.from == [2, 4] && second_jump.to == [4, 6], "Checkers did not expose the continuation of a multiple capture")
promotion_board = Array.new(8) { Array.new(8) }
promotion_board[6][0] = "0m"
promotion_state = checkers_start.state.merge(
  board: promotion_board, current_player: "Alice", forced_from: nil, last_to: nil,
  captured_this_turn: false, promoted_this_turn: false
)
checkers.send(:apply_move!, promotion_state, GameRoomGames::BoardMove.new(from: [0, 6], to: [1, 7]), "Alice")
assert(promotion_state[:board][7][1] == "0k", "Checkers did not promote a man on the final row")

puts 'PASS checkers: model rules and presentation'
