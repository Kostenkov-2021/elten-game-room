def _(text)
  text
end

module Session
  def self.name
    "Alice"
  end
end

module EltenLink
  class Error < StandardError; end
end

require_relative "../../lib/table_activity_repository"

def assert(condition, message)
  raise message if !condition
end

class FakeActivityTable
  attr_reader :rows

  def initialize
    @rows = []
  end

  def insert(values)
    row = values.merge(
      "__id" => @rows.length + 1,
      "__insertion_user" => values["actor"]
    )
    @rows << row
    row
  end

  def select(where: nil, order:, limit:)
    selected = @rows.select do |row|
      where == nil || where.all? { |key, value| row[key].to_s == value.to_s }
    end
    direction = order.to_a.first.to_a[1].to_s
    selected = selected.sort_by { |row| [row["created_at"].to_i, row["__id"].to_i] }
    selected.reverse! if direction == "desc"
    selected.take(limit.to_i)
  end
end

table = FakeActivityTable.new
server_tables = { "table_activity" => table }
room = {
  "__id" => 9,
  "__insertion_user" => "Alice",
  "owner" => "Alice",
  "game" => "spades"
}
repository = TableActivityRepository.new(server_tables: server_tables)
created = repository.append(table: room, kind: "created")
joined = repository.append(table: room, kind: "joined", actor: "Bob")
chat = repository.append(table: room, kind: "chat", actor: "Bob", message: "  hello\r\nthere  ")

assert(repository.entries_for(room).map(&:id) == [created.id, joined.id, chat.id], "table activity order changed")
assert(chat.message == "hello there", "chat text was not normalized")
assert(repository.text_for(chat, game_name: ->(_id) { "Spades" }) == "Bob: hello there", "chat history text is invalid")
assert(repository.global_entries.map(&:kind) == %w[created joined], "chat leaked into global history")
assert(repository.latest_global_id == joined.id, "the lobby change cursor did not ignore chat")
assert(
  repository.text_for(joined, game_name: ->(_id) { "Spades" }, global: true) == "Bob joined Alice's table for Spades.",
  "global join history is missing its master or game"
)

game_entry = Struct.new(:event_id, :text).new(51, "Alice played a card.")
game_event = { "__id" => 51, "created_at" => created.created_at }
merged = repository.merge_history(
  game_entries: [game_entry],
  game_events: [game_event],
  activity_entries: [created, joined, chat],
  game_name: ->(_id) { "Spades" }
)
assert(merged.include?("Alice played a card.") && merged.include?("Bob: hello there"), "shared history lost game or table events")
categorized = repository.merged_history_entries(
  game_entries: [game_entry],
  game_events: [game_event],
  activity_entries: [created, joined, chat],
  game_name: ->(_id) { "Spades" }
)
assert(
  categorized.map(&:category).sort_by(&:to_s) == [:chat, :game, :room, :room].sort_by(&:to_s),
  "shared history did not classify game, chat and room events"
)
assert(categorized.map(&:text) == merged, "categorized history changed chronological presentation")

left = repository.append(table: room, kind: "left", actor: "Bob")
rejoined = repository.append(table: room, kind: "joined", actor: "Bob")
assert(
  repository.entries_for(room, viewer: "Bob").map(&:id) == [rejoined.id],
  "a returning player received activity from an earlier room visit"
)
assert(
  repository.entries_for(room, viewer: "Alice").map(&:id) == [created.id, joined.id, chat.id, left.id, rejoined.id],
  "the table owner lost activity from the current table lifetime"
)

puts "Table activity repository tests passed"
