require_relative "../../../lib/game_surfaces/specifications"
def _(text)
  text
end


require_relative "../../../games/base"
require_relative "../../../games/four_in_a_row"

class FakeGameRepository
  def players_for(_session)
    ["Alice", "Bob"]
  end

  def actor_of(event, _session = nil)
    event.fetch("actor")
  end

  def event_id(event)
    event.fetch("id")
  end
end

class DrawingFourInARow < GameRoomGames::FourInARow
  def shortcut_features
    super + [:draw_card]
  end

  def shortcut_feature_data(feature, replay, viewer)
    return {
      kind: :action,
      action_kind: "command",
      action_name: "draw"
    } if feature.to_sym == :draw_card

    super
  end
end

def assert(condition, message)
  raise message if !condition
end

def events_for(columns)
  players = ["Alice", "Bob"]
  columns.each_with_index.map do |column, index|
    {
      "id" => index + 1,
      "actor" => players[index % 2],
      "action" => "drop",
      "value" => column.to_s
    }
  end
end

game = GameRoomGames::FourInARow.new
repository = FakeGameRepository.new
session = {}

assert(!game.respond_to?(:move_for), "four in a row still exposes the legacy move_for contract")
assert(game.minimum_players == 2, "four in a row does not declare its minimum player count")
assert(game.maximum_players == 2, "four in a row does not declare its maximum player count")
assert(game.supports_bots?, "four in a row does not expose bot support")

horizontal = game.replay(session, events_for([1, 7, 2, 7, 3, 6, 4]), repository)
assert(horizontal.winner == "Alice", "horizontal win was not detected")
assert(horizontal.accepted_events.length == 7, "horizontal replay lost a valid move")

mirrored_horizontal = game.replay(session, events_for([7, 1, 6, 1, 5, 2, 4]), repository)
assert(
  game.bot_search_key(horizontal, "Alice") == game.bot_search_key(mirrored_horizontal, "Alice"),
  "the Four in a Row search does not share equivalent mirrored positions"
)

vertical = game.replay(session, events_for([1, 2, 1, 2, 1, 2, 1]), repository)
assert(vertical.winner == "Alice", "vertical win was not detected")

invalid_double_move = [
  { "id" => 1, "actor" => "Alice", "action" => "drop", "value" => "1" },
  { "id" => 2, "actor" => "Alice", "action" => "drop", "value" => "2" },
  { "id" => 3, "actor" => "Bob", "action" => "drop", "value" => "3" }
]
replayed = game.replay(session, invalid_double_move, repository)
assert(replayed.accepted_events.map { |event| event["id"] } == [1, 3], "out-of-turn move was accepted")
assert(replayed.current_player == "Alice", "turn did not advance after valid events")

full_column = game.replay(session, events_for([1, 1, 1, 1, 1, 1]), repository)
assert(
  !game.legal_actions(full_column, full_column.current_player).any? { |action| action["x"] == 0 },
  "a full column was exposed to a bot"
)
status, move = game.action_for(
  { "kind" => "grid", "action" => "select", "x" => 0, "y" => 4 },
  full_column,
  full_column.current_player
)
assert(status == :column_full && move == nil, "full column was offered as a valid move")

empty = game.replay(session, [], repository)
empty_surface = game.surface_spec(empty, "Alice")
assert(empty_surface.cells.flatten.all?(&:empty?), "an empty Connect Four field says empty")
view = game.game_view_spec(empty, "Alice")
assert(view.is_a?(GameRoomLayout::ViewSpec), "four in a row bypasses the shared game layout")
assert(view.sections == [:status, :game, :chat, :history, :users], "four in a row changed the shared field order")
assert(view.surface.header == "Four in a row", "the board header still repeats the turn status")
turn_shortcut = game.game_shortcuts(empty, "Alice").find { |shortcut| shortcut.key == "t" }
assert(turn_shortcut != nil, "four in a row does not expose the shared turn shortcut")
assert(turn_shortcut.message == "It is your turn.", "the shared turn shortcut reports the wrong player")
draw_game = DrawingFourInARow.new
draw_replay = draw_game.replay(session, [], repository)
draw_shortcut = draw_game.game_shortcuts(draw_replay, "Alice").find { |shortcut| shortcut.key == "space" }
assert(draw_shortcut != nil, "the card-drawing capability did not register Space")
assert(draw_shortcut.kind == :action, "the card-drawing capability is not a direct action")
assert(draw_shortcut.action_name == "draw", "the card-drawing capability emits the wrong action")
legal_columns = game.legal_actions(empty, "Alice").map { |action| action["x"] }
assert(legal_columns == (0...7).to_a, "four in a row did not expose all legal columns")
status, move = game.action_for(
  { "kind" => "grid", "action" => "select", "x" => 3, "y" => 5 },
  empty,
  "Alice"
)
assert(
  status == :ok && move.events.first.action == "drop" && move.events.first.value == "4",
  "grid selection did not choose its column"
)

status, move = game.action_for(
  { "kind" => "dice", "action" => "toggle", "index" => 0 },
  empty,
  "Alice"
)
assert(status == :invalid && move == nil, "four in a row accepted an action from another surface")

surface = game.surface_spec(horizontal, "Alice")
assert(surface.width == 7 && surface.height == 6, "grid dimensions are incorrect")
assert(surface.row_origin == :bottom, "grid row origin is incorrect")
assert(surface.cells.length == 6 && surface.cells.all? { |row| row.length == 7 }, "grid cells are incomplete")
assert(surface.cells[0][0].include?("Alice"), "bottom-left piece is missing from the grid")

stacked = game.replay(session, events_for([1, 2, 1]), repository)
last_event = stacked.accepted_events.last
last_move = stacked.history.find { |entry| entry.event_id == 3 && entry.kind == :move }
assert(last_move.field == "A2", "history uses the cursor row instead of the landing field")
assert(last_move.text.include?("A2"), "history does not contain the full field coordinate")
assert(
  game.describe_event(last_event, repository, stacked, "Alice") == "Alice A2.",
  "the shared board announcement does not identify the player and landing field"
)
assert(
  game.describe_event(last_event, repository, stacked, "Bob").include?("A2"),
  "the other player is not told the full landing coordinate"
)

puts "Four in a row model tests passed"
