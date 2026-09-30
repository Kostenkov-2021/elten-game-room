require_relative "../../support/new_board_games"

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

puts 'PASS reversi: model rules and presentation'
