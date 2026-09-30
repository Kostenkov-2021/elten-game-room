# encoding: UTF-8
require_relative "../support/native_room_harness"
require_relative "../support/ui"

class Program
  def self.server_app(**_options); end
end
require_relative "../../__app"

class NamedActivityTable < ActivityTableDouble
  def insert(values)
    allowed = %w[table_id kind actor table_owner game message created_at]
    assert((values.keys - allowed).empty?, "name activity needs a new server column")
    super
  end

  def select(where: nil, order: nil, limit: nil, **_options)
    record_request(:select)
    rows = @rows.select { |row| where == nil || where.all? { |key, value| row[key] == value } }
    rows.sort_by! { |row| [row["created_at"].to_i, row["__id"]] }
    rows.reverse! if order.to_a.first.to_a[1] == "desc"
    rows.first(limit || rows.length)
  end
end

h = NativeRoomHarness.new(users: %w[Alice Bob])
table = NamedActivityTable.new
activities = h.users.to_h do |user|
  [user, TableActivityRepository.new(server_tables: { "table_activity" => table }, transport: h.transports[user])]
end
lobby = LobbyRepository.new(ProgramDouble.new(h.broker.endpoint("Alice")), transport: h.transports["Alice"],
  server_tables: {}, activity_repository: activities["Alice"])
tokens = %w[pl20 en03 pl11]
original_picker = GameRoomBotNames.method(:pick)
GameRoomBotNames.define_singleton_method(:pick) { |**_options| tokens.shift || raise("unexpected extra name draw") }
game_name = ->(_id) { "UNO" }
expected = []
added = []
begin
  3.times do
    record_count = h.core.entries.length
    write_count = table.calls.count(:insert)
    result = h.as("Alice") { lobby.add_bot(h.table, snapshot: lobby.snapshot_for(h.table)) }
    assert(result.updated?, "named bot addition failed")
    bot = result.snapshot.bots.last
    added << bot
    expected << "Added #{GameRoomParticipants.display_name(bot)}."
    assert(result.activity && result.activity.subject == bot, "addition history lost the chosen bot identity")
    assert(activities["Alice"].text_for(result.activity, game_name: game_name) == expected.last, "addition message omits name or adds Computer")
    assert(h.core.entries.length == record_count + 2, "name introduced an extra stack write")
    assert(table.calls.count(:insert) == write_count + 1, "name introduced an extra global write")
  end
ensure
  GameRoomBotNames.define_singleton_method(:pick, original_picker)
end

result = h.as("Alice") { lobby.remove_bot(h.table, snapshot: lobby.snapshot_for(h.table), participant: added[1]) }
assert(result.updated?, "named removal failed")
assert(result.activity.subject == added[1], "removal recorded a different bot after compacting seats")
expected << "Removed Noob's spirit."
assert(result.snapshot.bots.map { |bot| GameRoomParticipants.display_name(bot) } == ["Maślana", "brzydkie Kaczątko"], "removal changed the survivors")

# A late reader must render the original names even after the named bot has
# left and another bot now occupies its old slot. No lookup of current seats.
h.add_client("Carol")
assert(h.join("Carol"), "late reader could not join")
activities["Carol"] = TableActivityRepository.new(server_tables: { "table_activity" => table }, transport: h.transports["Carol"])
activities.each do |user, repository|
  entries = repository.entries_for(h.table)
  assert(entries.map { |entry| repository.text_for(entry, game_name: game_name) } == expected, "#{user}: replay changed the named history")
  assert(repository.merge_history(game_entries: [], game_events: [], activity_entries: entries, game_name: game_name) == expected, "#{user}: shared history differs from speech")
end
global = activities["Alice"].global_entries
assert(global.length == 4 && global.map(&:subject) == added + [added[1]], "global history dropped named computer activity")
assert(activities["Alice"].latest_global_id == global.last.id, "global cursor ignores named activities")
assert(activities["Alice"].text_for(global.first, game_name: game_name, global: true) == "Added Maślana at Alice's table for UNO.", "global message lost name or table context")
assert(activities["Alice"].text_for(global.last, game_name: game_name, global: true) == "Removed Noob's spirit from Alice's table for UNO.", "global removal message differs")

# Both the waiting-room speaker and the active-game speaker use the same
# history formatter, once per event; focusing or repainting must not repeat it.
entries = activities["Alice"].entries_for(h.table)
app = EltenGameRoom.allocate
app.instance_variable_set(:@table_activity, activities["Alice"])
spoken = []
app.define_singleton_method(:speak) { |text, **_options| spoken << text }
app.define_singleton_method(:game_name) { |_id| "UNO" }
cursor = app.send(:announce_new_table_activity, entries, after_id: 0)
app.send(:announce_new_table_activity, entries, after_id: cursor)
assert(spoken == expected, "waiting-room speech is generic or duplicated")
screen = GameScreen.allocate
screen.instance_variable_set(:@activity_repository, activities["Bob"])
screen.instance_variable_set(:@activity_entries, entries)
screen.send(:event_presenter).instance_variable_set(:@last_seen_activity_id, 0)
screen.instance_variable_set(:@game_name, game_name)
spoken = []
screen.define_singleton_method(:speak) { |text, **_options| spoken << text }
2.times { screen.send(:process_new_table_activity, nil) }
assert(spoken == expected, "active-game speech is generic or duplicated")

# A private room must keep the name inside its native log, not publish it.
private_table = h.as("Alice") do
  h.transports["Alice"].create_room(name: "Private test", game: "uno", owner: "Alice", game_options: "{}", private_table: true)
end
private_bot = GameRoomParticipants.bot_id(private_table["__id"], 1, name_token: "pl20")
write_count = table.calls.count(:insert)
private_entry = h.as("Alice") { activities["Alice"].append(table: private_table, kind: "bot_added", subject: private_bot) }
assert(table.calls.count(:insert) == write_count, "private name leaked into lobby history")
assert(activities["Alice"].text_for(private_entry, game_name: game_name) == "Added Maślana.", "private history lost name")

# Stored activity must remain interpretable without server schema extensions;
# malformed metadata and names belonging to another table are rejected.
["bot:#{h.table['__id'] + 1}:1:pl20", "bot:0:1:pl20", "bot:#{h.table['__id']}:0:pl20", "invalid"].each do |subject|
  begin
    activities["Alice"].append(table: h.table, kind: "bot_added", subject: subject)
  rescue ArgumentError
    next
  end
  raise "invalid bot activity accepted: #{subject}"
end

puts "Named bot activity: add/remove, stable history, three readers, lobby, both speech paths, no extra writes or private leaks: OK"
