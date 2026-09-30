require_relative "../../../lib/game_surfaces/specifications"
def _(text)
  text
end


require_relative "../../../games/base"
require_relative "../../../games/tic_tac_toe"
require_relative "../../../games/registry"

class FakeTicTacToeRepository
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

def assert(condition, message)
  raise message if !condition
end

def events_for(moves)
  players = ["Alice", "Bob"]
  moves.each_with_index.map do |field, index|
    {
      "id" => index + 1,
      "actor" => players[index % 2],
      "action" => "place",
      "value" => field
    }
  end
end

game = GameRoomGames::TicTacToe.new
repository = FakeTicTacToeRepository.new
session = {}

assert(!game.respond_to?(:move_for), "tic-tac-toe still exposes the legacy move_for contract")
assert(game.id == "tic_tac_toe", "tic-tac-toe has an invalid id")
assert(game.minimum_players == 2 && game.maximum_players == 2, "tic-tac-toe has invalid player limits")
assert(game.supports_bots?, "tic-tac-toe does not expose bot support")

horizontal = game.replay(session, events_for(["1,1", "1,2", "2,1", "2,2", "3,1"]), repository)
assert(horizontal.winner == "Alice", "horizontal win was not detected")
assert(horizontal.accepted_events.length == 5, "a valid tic-tac-toe move was lost")

diagonal = game.replay(session, events_for(["1,1", "1,2", "2,2", "2,1", "3,3"]), repository)
assert(diagonal.winner == "Alice", "diagonal win was not detected")

draw = game.replay(
  session,
  events_for(["1,1", "2,1", "3,1", "1,2", "3,2", "2,2", "1,3", "3,3", "2,3"]),
  repository
)
assert(draw.draw == true && draw.winner == nil, "draw was not detected")

invalid = [
  { "id" => 1, "actor" => "Alice", "action" => "place", "value" => "1,1" },
  { "id" => 2, "actor" => "Bob", "action" => "place", "value" => "1,1" },
  { "id" => 3, "actor" => "Bob", "action" => "place", "value" => "2,1" }
]
replayed = game.replay(session, invalid, repository)
assert(replayed.accepted_events.map { |event| event["id"] } == [1, 3], "occupied field changed the turn")

empty = game.replay(session, [], repository)
empty_surface = game.surface_spec(empty, "Alice")
assert(empty_surface.cells.flatten.all?(&:empty?), "an empty Tic-tac-toe field says empty")
view = game.game_view_spec(empty, "Alice")
assert(view.is_a?(GameRoomLayout::ViewSpec), "tic-tac-toe bypasses the shared game layout")
assert(view.sections == [:status, :game, :chat, :history, :users], "tic-tac-toe changed the shared field order")
assert(view.surface.header == "Tic-tac-toe", "the board header still repeats the turn status")
assert(game.legal_actions(empty, "Alice").length == 9, "tic-tac-toe did not expose all empty fields")
status, move = game.action_for(
  { "kind" => "grid", "action" => "select", "x" => 2, "y" => 1 },
  empty,
  "Alice"
)
assert(
  status == :ok && move.events.first.action == "place" && move.events.first.value == "3,2",
  "grid selection produced an invalid move"
)

occupied = game.replay(session, events_for(["1,1"]), repository)
assert(
  game.legal_actions(occupied, "Bob").none? { |action| action["x"] == 0 && action["y"] == 0 },
  "an occupied field was exposed to a bot"
)
status, move = game.action_for(
  { "kind" => "grid", "action" => "select", "x" => 0, "y" => 0 },
  occupied,
  "Bob"
)
assert(status == :occupied && move == nil, "an occupied field was offered as a valid move")
assert(game.move_error(status).include?("occupied"), "occupied field has no specific message")

status, move = game.action_for(
  { "kind" => "question", "action" => "submit", "answer" => "A1" },
  empty,
  "Alice"
)
assert(status == :invalid && move == nil, "tic-tac-toe accepted an action from another surface")

surface = game.surface_spec(horizontal, "Alice")
assert(surface.width == 3 && surface.height == 3, "tic-tac-toe grid dimensions are incorrect")
assert(surface.row_origin == :bottom, "tic-tac-toe coordinates do not start at the bottom")

last_event = horizontal.accepted_events.last
last_move = horizontal.history.find { |entry| entry.kind == :move && entry.event_id == 5 }
assert(last_move.field == "C1", "tic-tac-toe history has an invalid coordinate")
assert(
  game.describe_event(last_event, repository, horizontal, "Alice") == "Alice C1.",
  "the shared board announcement does not identify the player and field"
)

registry = GameRoomGames::Registry.new([
  GameRoomGames::TicTacToe
])
assert(registry.ids == ["tic_tac_toe"], "game registry lost tic-tac-toe")
assert(registry.build("tic_tac_toe").is_a?(GameRoomGames::TicTacToe), "game registry could not build a game")
assert(registry.build("missing") == nil, "game registry accepted an unknown game")

puts "Tic-tac-toe model tests passed"
