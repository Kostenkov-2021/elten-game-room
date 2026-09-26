require_relative 'support/new_board_games'

players = ["Alice", "Bob"]
repository = NewGamesRepository.new(players)
session = { "options" => "{}" }

reversi = GameRoomGames::Reversi.new
reversi_start = reversi.replay(session, [], repository)
assert(reversi.supports_bots?, "Reversi has no bot")
assert(reversi_start.board.length == 8 && reversi_start.board.flatten.compact.length == 4, "Reversi has an invalid initial board")
reversi_actions = reversi.legal_actions(reversi_start, "Alice")
assert(reversi_actions.length == 4, "Reversi does not expose the four opening moves")
occupied_status, = reversi.action_for(
  { "kind" => "grid", "action" => "select", "x" => 3, "y" => 3 },
  reversi_start,
  "Alice"
)
assert(occupied_status == :occupied, "Reversi did not distinguish an occupied field")
assert(reversi.move_error(occupied_status) == "This field is already occupied.", "Reversi did not explain the occupied field")
assert(
  reversi.move_error_for(
    occupied_status,
    selection: { "x" => 3, "y" => 3 },
    replay: reversi_start,
    actor: "Alice"
  ) == "Field D4 is already occupied.",
  "Reversi did not identify the occupied field"
)
empty_invalid_status, = reversi.action_for(
  { "kind" => "grid", "action" => "select", "x" => 0, "y" => 0 },
  reversi_start,
  "Alice"
)
assert(empty_invalid_status == :invalid_move, "Reversi changed its empty illegal-field status")
assert(
  reversi.move_error(empty_invalid_status) == "A disc placed here would not enclose any opposing discs.",
  "Reversi lost its no-enclosure explanation"
)
reversi_events = []
reversi_after = append_surface_action(reversi, session, repository, reversi_events, reversi_start, "Alice", reversi_actions.first)
assert(reversi_after.board.flatten.count(0) == 4, "Reversi did not turn an enclosed disc")
assert(reversi_after.current_player == "Bob", "Reversi did not advance the turn")
assert(
  reversi.describe_event(reversi_events.last, repository, reversi_after, "Bob") == "Alice, changed fields: D3, D4.",
  "Reversi did not announce every changed field concisely"
)
reversi_pass_found = false
40.times do |seed|
  break if reversi_pass_found

  pass_events = []
  pass_replay = reversi.replay(session, pass_events, repository)
  random = Random.new(seed)
  64.times do
    break if pass_replay.finished?

    actions = reversi.legal_actions(pass_replay, pass_replay.current_player)
    raise "Reversi exposed an active turn without a legal move" if actions.empty?
    previous_passes = pass_replay.history.count { |entry| entry.kind == :pass }
    pass_replay = append_surface_action(
      reversi,
      session,
      repository,
      pass_events,
      pass_replay,
      pass_replay.current_player,
      actions[random.rand(actions.length)]
    )
    if pass_replay.history.count { |entry| entry.kind == :pass } > previous_passes
      reversi_pass_found = true
      break
    end
  end
end
assert(reversi_pass_found, "Reversi no longer passes a turn automatically after announcing that no move is available")

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
assert(checkers_surface.coordinate_label_sets["numeric"][7][0] == "1", "Checkers numbering does not begin at the upper left playable field")
assert(checkers_surface.coordinate_label_sets["numeric"][0][1] == "29", "Checkers numbering does not end on the lower rows")
assert(checkers_surface.coordinate_label_sets["algebraic"][0][0] == "A1", "Checkers algebraic notation omits a light field")
assert(checkers_surface.coordinate_label_sets["algebraic"][0][1] == "B1", "Checkers algebraic notation omits a playable field")
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
assert(checkers_surface.pieces[0][1].label == "white man", "Checkers does not describe a piece by colour and kind")
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
assert(international_labels[9][0] == "1", "International checkers does not begin with field 1")
assert(international_labels[6][9] == "20", "International checkers does not end the upper setup on field 20")
assert(international_labels[5][0] == "21" && international_labels[4][9] == "30", "International checkers middle fields are not 21 through 30")
assert(international_labels[3][0] == "31" && international_labels[0][9] == "50", "International checkers lower setup is not 31 through 50")
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
assert(algebraic_history.last.text.include?("from B3 to A4"), "Checkers history did not apply the local algebraic-notation filter")
assert(checkers_after.history.last.text.include?("from 21 to 17"), "The local history filter changed the authoritative replay history")
capture_board = Array.new(8) { Array.new(8) }
capture_board[2][1] = "0m"
capture_board[2][5] = "0m"
capture_board[3][2] = "1m"
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
assert(capture_actions.first["to_x"] == 3 && capture_actions.first["to_y"] == 4, "Checkers generated the wrong capture")
capture_surface = checkers.surface_spec(capture_replay, "Alice")
non_capturing_piece = capture_surface.pieces[2][5]
mandatory_message = capture_surface.origin_error.call(
  [5, 2],
  "unused piece",
  non_capturing_piece,
  ->(position) { position == [1, 2] ? "21" : position.join(",") }
)
assert(
  mandatory_message == "Capturing is mandatory. Choose a piece on 21.",
  "Checkers did not identify mandatory capturing or the selectable piece"
)
sequence_board = Array.new(8) { Array.new(8) }
sequence_board[2][1] = "0m"
sequence_board[3][2] = "1m"
sequence_board[5][4] = "1m"
sequence_state = checkers_start.state.merge(
  board: sequence_board, current_player: "Alice", forced_from: nil, last_to: nil,
  captured_this_turn: false, promoted_this_turn: false
)
first_jump = checkers.send(:moves_for_state, sequence_state, "Alice").first
checkers.send(:apply_move!, sequence_state, first_jump, "Alice")
assert(sequence_state[:forced_from] == [3, 4], "Checkers did not retain the moving piece during a multiple capture")
second_jump = checkers.send(:moves_for_state, sequence_state, "Alice").first
assert(second_jump.from == [3, 4] && second_jump.to == [5, 6], "Checkers did not expose the continuation of a multiple capture")
promotion_board = Array.new(8) { Array.new(8) }
promotion_board[6][1] = "0m"
promotion_state = checkers_start.state.merge(
  board: promotion_board, current_player: "Alice", forced_from: nil, last_to: nil,
  captured_this_turn: false, promoted_this_turn: false
)
checkers.send(:apply_move!, promotion_state, GameRoomGames::BoardMove.new(from: [1, 6], to: [0, 7]), "Alice")
assert(promotion_state[:board][7][0] == "0k", "Checkers did not promote a man on the final row")

chess = GameRoomGames::Chess.new
chess_events = []
chess_replay = chess.replay(session, chess_events, repository)
assert(chess.supports_bots?, "Chess has no bot")
assert(chess.legal_actions(chess_replay, "Alice").length == 20, "Chess does not expose 20 legal opening moves")
chess_surface = chess.surface_spec(chess_replay, "Alice")
assert(chess_surface.pieces[0][0].label == "white rook", "Chess does not describe a piece by colour and kind")
assert(chess_surface.default_orientation == "normal", "The first chess player does not start at the bottom")
assert(chess.surface_spec(chess_replay, "Bob").default_orientation == "rotated", "The second chess player does not start at the bottom")
chess_empty_message = chess_surface.origin_error.call([0, 2], "A3", nil, ->(position) { position.join(",") })
assert(chess_empty_message == "Field A3 is empty.", "Chess did not explain an empty field")
blocked_rook = chess_surface.pieces[0][0]
blocked_rook_message = chess_surface.origin_error.call([0, 0], "A1", blocked_rook, ->(position) { position.join(",") })
assert(blocked_rook_message.include?("has no legal move"), "Chess did not explain a blocked piece")
blocked_path_message = chess_surface.destination_error.call(
  [0, 0], [0, 3], "A1", "A4", blocked_rook, nil, ->(position) { position.join(",") }
)
assert(blocked_path_message == "The path from A1 to A4 is blocked.", "Chess did not explain a blocked path")
own_rook = chess_surface.pieces[0][0]
white_knight = chess_surface.pieces[0][1]
own_occupied_message = chess_surface.destination_error.call(
  [1, 0], [0, 0], "B1", "A1", white_knight, own_rook, ->(position) { position.join(",") }
)
assert(own_occupied_message.include?("is occupied by your"), "Chess did not explain a destination occupied by an own piece")
castle_blocked_message = chess_surface.destination_error.call(
  [4, 0], [6, 0], "E1", "G1", chess_surface.pieces[0][4], nil, ->(position) { position.join(",") }
)
assert(castle_blocked_message.include?("path between the king and rook is blocked"), "Chess did not explain blocked castling")

pinned_board = Array.new(8) { Array.new(8) }
pinned_board[0][4] = "wK"
pinned_board[1][4] = "wB"
pinned_board[7][4] = "bR"
pinned_board[7][0] = "bK"
pinned_state = chess.send(:initial_state, players).merge(board: pinned_board, current_player: "Alice", castling: "", en_passant: nil)
pinned_replay = chess_replay.dup
pinned_replay.board = pinned_board
pinned_replay.state = pinned_state
pinned_replay.current_player = "Alice"
pinned_surface = chess.surface_spec(pinned_replay, "Alice")
pinned_piece = pinned_surface.pieces[1][4]
pinned_message = pinned_surface.origin_error.call([4, 1], "E2", pinned_piece, ->(position) { position.join(",") })
assert(pinned_message.include?("expose your king to check"), "Chess did not explain a pinned piece")
pinned_destination_message = pinned_surface.destination_error.call(
  [4, 1], [5, 2], "E2", "F3", pinned_piece, nil, ->(position) { position.join(",") }
)
assert(pinned_destination_message == "This move would leave your king in check.", "Chess did not explain a self-check move")
chess_shortcuts = chess.game_shortcuts(chess_replay, "Alice")
%w[k d r b n p].each do |key|
  assert(chess_shortcuts.any? { |shortcut| shortcut.key == key && shortcut.kind == :surface }, "Chess has no #{key.upcase} piece-navigation shortcut")
end
assert(chess_shortcuts.any? { |shortcut| shortcut.key == "e" && shortcut.kind == :surface }, "Chess has no threat shortcut")
assert(chess_shortcuts.any? { |shortcut| shortcut.key == "v" && shortcut.kind == :surface }, "Chess has no legal-move shortcut")
threat_board = Array.new(8) { Array.new(8) }
threat_board[0][0] = "wK"
threat_board[7][7] = "bK"
threat_board[7][0] = "bR"
threat_state = chess.send(:initial_state, players).merge(board: threat_board, castling: "", en_passant: nil)
threats = chess.send(:square_threat_details, threat_state, "Alice")
assert(threats[2][0] == "A3 is attacked by black rook from A8.", "Chess E does not identify a threat on an empty field")
assert(threats[2][1] == "No opposing piece attacks B3.", "Chess E does not report an unattacked empty field")
[
  ["Alice", [4, 1], [4, 3]],
  ["Bob", [4, 6], [4, 4]],
  ["Alice", [5, 0], [2, 3]],
  ["Bob", [1, 7], [2, 5]],
  ["Alice", [3, 0], [7, 4]],
  ["Bob", [6, 7], [5, 5]],
  ["Alice", [7, 4], [5, 6]]
].each do |actor, from, to|
  action = chess.legal_actions(chess_replay, actor).find do |candidate|
    [candidate["from_x"], candidate["from_y"]] == from && [candidate["to_x"], candidate["to_y"]] == to
  end
  raise "expected chess move #{from.inspect} to #{to.inspect} is missing" if action == nil
  chess_replay = append_surface_action(chess, session, repository, chess_events, chess_replay, actor, action)
end
assert(chess_replay.winner == "Alice", "Chess did not detect checkmate")
assert(chess_replay.current_player == nil, "Chess left a turn active after checkmate")
assert(
  chess.describe_event(chess_events.first, repository, chess_replay, "Bob").to_s.include?("white pawn from"),
  "Chess did not expose its move announcement"
)
empty_chess = Array.new(8) { Array.new(8) }
empty_chess[0][4] = "wK"
empty_chess[0][7] = "wR"
empty_chess[7][4] = "bK"
castle_state = chess.send(:initial_state, players).merge(
  board: empty_chess, current_player: "Alice", castling: "K", en_passant: nil,
  pending_promotion: nil, positions: Hash.new(0)
)
castle = chess.send(:legal_moves, castle_state, "Alice").find { |move| move.from == [4, 0] && move.to == [6, 0] }
assert(castle != nil && castle.metadata["castle"] == "king", "Chess did not allow legal king-side castling")
en_passant_board = Array.new(8) { Array.new(8) }
en_passant_board[0][4] = "wK"
en_passant_board[7][4] = "bK"
en_passant_board[4][4] = "wP"
en_passant_board[4][3] = "bP"
en_passant_state = castle_state.merge(board: en_passant_board, castling: "", en_passant: [3, 5])
en_passant = chess.send(:legal_moves, en_passant_state, "Alice").find { |move| move.from == [4, 4] && move.to == [3, 5] }
assert(en_passant != nil && en_passant.metadata["en_passant"] == "1", "Chess did not expose en passant")
promotion_chess_board = Array.new(8) { Array.new(8) }
promotion_chess_board[0][4] = "wK"
promotion_chess_board[7][4] = "bK"
promotion_chess_board[6][0] = "wP"
promotion_chess_state = castle_state.merge(board: promotion_chess_board, castling: "", en_passant: nil)
chess.send(:apply_chess_move!, promotion_chess_state, GameRoomGames::BoardMove.new(from: [0, 6], to: [0, 7]), "Alice")
assert(promotion_chess_state[:pending_promotion] == [0, 7], "Chess skipped the promotion choice")

ludo_players = ["Alice", "Bob", "Carol", "Dave"]
ludo_repository = NewGamesRepository.new(ludo_players)
ludo = GameRoomGames::Ludo.new
ludo_replay = ludo.replay(session, [], ludo_repository)
assert(ludo.minimum_players == 2 && ludo.maximum_players == 4, "Ludo has invalid player limits")
assert(ludo_replay.state[:pawns].all? { |pawns| pawns == [-1, -1, -1, -1] }, "Ludo pawns do not start in their bases")
ludo_shortcuts = ludo.game_shortcuts(ludo_replay, "Alice")
own_pawns_shortcut = ludo_shortcuts.find { |shortcut| shortcut.key == "p" && shortcut.modifiers.empty? }
opponent_pawns_shortcut = ludo_shortcuts.find { |shortcut| shortcut.key == "p" && shortcut.modifiers == [:shift] }
own_pawn_list = ludo_shortcuts.find { |shortcut| shortcut.key == "v" && shortcut.modifiers.empty? }
all_pawn_list = ludo_shortcuts.find { |shortcut| shortcut.key == "v" && shortcut.modifiers == [:shift] }
assert(own_pawns_shortcut&.message == "Alice: In base: 4.", "Ludo P does not group base pawns")
assert(opponent_pawns_shortcut&.message.to_s.include?("Bob: In base: 4"), "Ludo Shift+P does not report opposing pawn positions")
assert(own_pawn_list&.kind == :browse && own_pawn_list.choices.map(&:label) == ["Alice, base"] * 4, "Ludo V does not expose one own pawn per row")
assert(all_pawn_list&.kind == :browse && all_pawn_list.choices.length == 16, "Ludo Shift+V does not expose every pawn in one list")
assert(all_pawn_list.choices.first.label == "Alice, base", "Ludo Shift+V does not identify the owner before its position")
ludo_waiting_surface = ludo.surface_spec(ludo_replay, "Alice")
ludo_track_spec = ludo_waiting_surface
assert(ludo_track_spec.is_a?(GameSurfaces::PawnTrackSpec), "Ludo still exposes a spatial board")
assert(ludo_track_spec.activation_action&.kind == "dice" && ludo_track_spec.activation_action&.name == "roll", "Ludo pawn list Enter does not roll the die")
assert(ludo_track_spec.header == "Ludo", "Ludo exposes pawn positions in the main field header")
assert(ludo_track_spec.items.map(&:label) == ["Roll the die"], "Ludo exposes pawn positions before rolling")
two_player_ludo = ludo.replay(session, [], NewGamesRepository.new(["Alice", "Bob"]))
assert(ludo.surface_spec(two_player_ludo, "Alice").items.length == 1, "Two-player Ludo did not expose the compact pawn list")
assert(ludo.surface_spec(two_player_ludo, "Bob").items.map(&:label) == ["Waiting for Alice"], "Ludo exposes pawn positions while waiting")
ludo_events = [{ "id" => 1, "actor" => "Alice", "action" => "roll", "value" => "6" }]
ludo_rolled = ludo.replay(session, ludo_events, ludo_repository)
assert(ludo_rolled.state[:phase] == :moving, "A Ludo 6 did not open pawn selection")
assert(ludo.legal_actions(ludo_rolled, "Alice").length == 4, "A Ludo 6 cannot release every base pawn")
invalid_pawn_status, = ludo.action_for({ "kind" => "pawn", "action" => "move" }, ludo_rolled, "Alice")
assert(invalid_pawn_status == :invalid_move, "Ludo treated a missing pawn number as pawn 1")
move_surface = ludo.surface_spec(ludo_rolled, "Alice")
assert(move_surface.items.length == 4, "Ludo did not list every legal pawn choice")
assert(move_surface.items.all? { |item| item.label.include?("base") && item.label.include?("track 1") }, "Ludo move choices do not preview semantic destinations")
assert(ludo.describe_event(ludo_events.first, ludo_repository, ludo_rolled, "Bob").include?("Alice rolled 6."), "Ludo did not announce a die roll")
ludo_after = append_surface_action(ludo, session, ludo_repository, ludo_events, ludo_rolled, "Alice", ludo.legal_actions(ludo_rolled, "Alice").first)
assert(ludo_after.state[:pawns][0].count(0) == 1, "Ludo did not move a pawn out of the base")
assert(ludo_after.current_player == "Alice" && ludo_after.state[:phase] == :awaiting_roll, "Ludo did not award the classic extra roll after a 6")
assert(
  ludo.describe_event(ludo_events.last, ludo_repository, ludo_after, "Bob").to_s.include?("Alice moved pawn"),
  "Ludo did not expose its pawn-move announcement"
)
assert(ludo.game_shortcuts(ludo_after, "Alice").find { |shortcut| shortcut.key == "p" && shortcut.modifiers.empty? }.message == "Alice: In base: 3; track 1.", "Ludo P did not report semantic pawn positions")
finished_pawns = Marshal.load(Marshal.dump(ludo_after))
finished_pawns.state[:pawns][0] = [GameRoomGames::Ludo::FINISH_PROGRESS, 0, -1, -1]
assert(
  ludo.game_shortcuts(finished_pawns, "Alice").find { |shortcut| shortcut.key == "p" && shortcut.modifiers.empty? }.message == "Alice: In base: 2; track 1; At the finish: 1 of 4 pawns.",
  "Ludo P did not aggregate pawns that reached the finish"
)
finish_state = ludo_replay.state.merge(
  phase: :moving, roll: 2, pawns: [[56, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1]]
)
assert(!ludo.send(:legal_pawn_indices, finish_state, 0).include?(0), "Ludo allowed a pawn to overshoot the finish")
finish_state[:roll] = 1
assert(ludo.send(:legal_pawn_indices, finish_state, 0).include?(0), "Ludo rejected an exact finishing roll")
finished_state = Marshal.load(Marshal.dump(finish_state))
finished_state[:pawns][0][0] = GameRoomGames::Ludo::FINISH_PROGRESS
[true, false].each do |exact_finish|
  finished_state[:options]["exact_finish"] = exact_finish
  assert(
    !ludo.send(:legal_pawn_indices, finished_state, 0).include?(0),
    "Ludo allowed a pawn at the finish to move when exact_finish was #{exact_finish}"
  )
end

# When only one move exists, the roll and move are one replayed server event.
# Replaying that same event cannot submit or apply a second move.
forced_events = ludo_events + [{ "id" => 3, "actor" => "Alice", "action" => "roll", "value" => "2" }]
forced_replay = ludo.replay(session, forced_events, ludo_repository)
assert(forced_replay.state[:pawns][0][0] == 2, "Ludo did not perform the only legal pawn move automatically")
assert(forced_replay.current_player == "Bob", "Ludo did not advance after its automatic pawn move")
forced_messages = ludo.describe_event(forced_events.last, ludo_repository, forced_replay, "Bob")
assert(forced_messages.any? { |message| message.include?("rolled 2") }, "The automatic move lost its roll announcement")
assert(forced_messages.any? { |message| message.include?("track 1 to track 3") }, "The automatic move lost its semantic move announcement")
forced_again = ludo.replay(session, forced_events, ludo_repository)
assert(forced_again.state[:pawns] == forced_replay.state[:pawns], "Replaying an automatic move applied it twice")

capture_state = ludo.send(:initial_state, ludo_players, ludo.default_options)
capture_state[:current_player] = "Alice"
capture_state[:phase] = :moving
capture_state[:roll] = 2
capture_state[:pawns][0][0] = 0
# Bob's progress 41 and Alice's progress 2 both refer to shared track field 3.
capture_state[:pawns][1][0] = 41
capture_history = []
ludo.send(:apply_pawn_move_index!, capture_state, "Alice", 0, 0, 501, capture_history)
assert(capture_state[:pawns][1][0] == -1, "Ludo did not return the captured pawn to its base")
assert(
  capture_history.any? { |entry| entry.kind == :capture && entry.text == "Alice sent pawn 1 belonging to Bob back to the base." },
  "Ludo capture announcement does not identify the captured pawn and its owner"
)

ludo_rules = ludo.rule_book.sections.flat_map(&:paragraphs).join(" ")
assert(ludo_rules.include?("1, 14, 27 and 40"), "Ludo rules do not explain the different shared-track starting fields")
assert(ludo_rules.include?("wraps from 52 back to 1"), "Ludo rules do not explain shared-track wrapping")

[reversi, checkers, chess, ludo].each do |game|
  assert(!game.rule_book.sections.empty?, "#{game.id} has no rules")
  assert(game.bot_strategy != nil, "#{game.id} has no bot strategy")
end

# Every new bot must be able to choose and submit a legal production action.
[reversi, checkers, chess, ludo].each do |game|
  count = [game.minimum_players, 2].max
  bot_players = (1..count).map { |index| "Computer #{index}" }
  environment = GameRoomSimulation::Environment.new_game(game: game, players: bot_players, seed: 165)
  actor = environment.active_actor
  actions = environment.legal_actions(actor)
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  choice = GameRoomBots.choose(game.bot_strategy, {
    actions: actions,
    observation: environment.observation(actor),
    actor: actor,
    random_source: environment.random_source,
    game: game,
    replay: environment.replay,
    context: environment.context,
    simulation: environment
  })
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
  assert(choice != nil, "#{game.id} bot did not choose a move")
  assert(environment.step(choice, actor: actor) == :ok, "#{game.id} bot produced an illegal move")
  stats = game.bot_strategy.respond_to?(:last_stats) ? game.bot_strategy.last_stats : {}
  puts "#{game.id} first bot decision: #{format('%.3f', elapsed)} seconds; #{stats.inspect}"
end

puts "New board game model tests passed"
