def _(text)
  text
end

require_relative "../../lib/game_history_navigation"

def assert(condition, message)
  raise message if !condition
end

entries = [
  GameRoomHistory::Entry.new(text: "room opened", category: :room),
  GameRoomHistory::Entry.new(text: "first move", category: :game),
  GameRoomHistory::Entry.new(text: "Alice: hello", category: :chat),
  GameRoomHistory::Entry.new(text: "second move", category: :game)
]
navigator = GameRoomHistory::Navigator.new

assert(navigator.move(entries, -1) == "second move", "the first history movement did not start at the newest entry")
assert(navigator.move(entries, -1) == "Alice: hello", "history did not move to the previous entry")
assert(navigator.jump(entries, :first) == "room opened", "history did not jump to its beginning")

game_category = navigator.change_category(entries, 1)
assert(game_category == "Game", "game history category announced more than its short name")
assert(navigator.move(entries, -1) == "first move", "filtered game history did not move between game events")
chat_category = navigator.change_category(entries, 1)
assert(chat_category == "Chat", "chat history category announced more than its short name")
room_category = navigator.change_category(entries, 1)
assert(room_category == "Room events", "room history category announced more than its short name")
all_category = navigator.change_category(entries, 1)
assert(all_category == "All", "history categories did not wrap back to the short all label")

puts "Game history navigation tests passed"
