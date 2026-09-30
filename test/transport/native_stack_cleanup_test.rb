require_relative "../support/native_room_harness"
require_relative "../support/log"

h = NativeRoomHarness.new(users: %w[Alice Bob], bots: 2)
h.start
owner = h.transports.fetch("Alice")
owner.update_room(h.table, { "status" => "playing", "game_options" => '{"variant":"test"}' }, actor: "Alice")
old_chat = owner.append_activity(table: h.table, kind: "chat", actor: "Alice", message: "already displayed")
h.broker.automatic_delivery = false
view = h.view("Alice")
assert(h.core.stack_entries == 4096 && h.core.stack_entry_bytes == 16384, "fake broker ignores requested stack limits")
packet = { "version" => 2, "kind" => "room_activity", "actor" => "Alice",
  "data" => { "activity_kind" => "chat", "message" => "old message" } }
# Leave exactly enough room for the checkpoint and confirmed start.
while h.core.entries.length < 4094
  view.stack_push(packet, message_id: SecureRandom.uuid)
end
native_id = h.core.id
before_sequence = h.core.last_seq
h.start
assert(h.core.id == native_id && h.core.participants.length == 2, "cleanup migrated or disconnected the session")
assert(h.core.entries.length == 2 && h.core.trimmed_through == before_sequence,
  "new game did not release the old stack at the actual 4096-entry boundary")
assert(h.core.last_seq == before_sequence + 2, "cleanup reused sequence numbers")
assert(owner.activity_records(h.table).any? { |entry| entry["__id"] == old_chat["__id"] },
  "cleanup erased chat already received in this client")

# Dave never belonged to the old game. Bob missed the new start and the trim.
h.add_client("Dave")
assert(h.join("Dave"), "late join failed after trimming")
bob_reads = h.view("Bob").calls[:read]
h.broker.deliver(user: "Bob")
assert(h.view("Bob").calls[:read] == bob_reads, "a gap callback performed a blocking stack read")
["Bob", "Dave"].each do |user|
  transport = h.transports.fetch(user)
  room = transport.room_snapshot(h.table)
  assert(room[:bots].length == 2 && room[:table]["status"] == "playing" && room[:table]["game_options"] == '{"variant":"test"}',
    "#{user} lost the checkpointed room state")
  current = h.repositories.fetch(user).session_for_table(h.table)
  assert(current["__id"] == h.session["__id"], "#{user} opened the previous game after trimming")
end
assert(h.transports.fetch("Dave").activity_records(h.table).empty?, "a fresh client inherited old chat history")
h.write("Alice", [GameRoomGames::EventCommand.new(action: "tick", value: "new game")])
assert(h.events("Dave").length == 1, "fresh client could not validate new-game moves")

# Concurrent chat written after the checkpoint must never be included in trim.
push = view.method(:stack_push)
view.define_singleton_method(:stack_push) do |value, message_id:|
  result = push.call(value, message_id: message_id)
  if value["kind"] == "game_started"
    h.transports.fetch("Bob").append_activity(table: h.table, kind: "chat", actor: "Bob", message: "during cleanup")
  end
  result
end
h.start
assert(h.core.entries.any? { |entry| entry.dig("packet", "data", "message") == "during cleanup" },
  "cleanup erased a concurrent message")
view.define_singleton_method(:stack_push, push)

# Never trim before a successful start acknowledgement. A rejected write and
# an accepted write with a lost acknowledgement both leave the old log intact.
[:before, :after].each do |phase|
  through = h.core.trimmed_through
  view.define_singleton_method(:stack_push) do |value, message_id:|
    self.fail_next_push = phase if value["kind"] == "game_started"
    push.call(value, message_id: message_id)
  end
  begin
    h.start
    raise "expected a lost start acknowledgement"
  rescue EltenAPI::LiveSessions::TimeoutError
  end
  assert(h.core.trimmed_through == through, "#{phase}-start failure removed unconfirmed history")
end
view.define_singleton_method(:stack_push, push)

# A single game can still fill the bounded log: enforce both real limits and
# leave the existing entries untouched on either rejection.
full = NativeRoomHarness.new(users: ["Alice"])
full.broker.automatic_delivery = false
full_view = full.view("Alice")
while full.core.entries.length < 4096
  full_view.stack_push(packet, message_id: SecureRandom.uuid)
end
begin
  full_view.stack_push(packet, message_id: SecureRandom.uuid)
  raise "the fake stack no longer enforces capacity"
rescue EltenAPI::LiveSessions::StackFull
end
assert(full.core.entries.length == 4096, "rejected push changed the stack")
small = NativeRoomHarness.new(users: ["Alice"])
begin
  small.view("Alice").stack_push({ "oversized" => "x" * 16384 }, message_id: SecureRandom.uuid)
  raise "the fake stack no longer enforces packet size"
rescue EltenAPI::LiveSessions::StackPacketTooLarge
end
puts "Native stack cleanup tests passed: capacity, checkpoints, late readers, concurrent chat and uncertain writes"
