require_relative "../../support/new_board_games"

players = ["Alice", "Bob"]
repository = NewGamesRepository.new(players)
session = { "options" => "{}" }

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

puts 'PASS chess: model rules and presentation'
