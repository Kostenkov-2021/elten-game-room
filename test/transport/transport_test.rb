require_relative "../support/native_room_harness"

h = NativeRoomHarness.new(users: %w[Alice Bob])
assert(h.transports.values.all?(&:live_store?), "default transport is not the native stack")
assert(h.core.participants.length == 2, "public discovery join lost a participant")
h.add_client("Carol")
bob = h.transports.fetch("Bob")
invitations = InvitationRepository.new(transport: bob)
sent = invitations.deliver(table: h.table, sender: "Bob", recipient: "Carol") do |row|
  bob.invite_user(table_id: h.table["__id"], user: "Carol", metadata: { "invitation_id" => row["__id"] })
end
assert(sent&.created?, "an ordinary participant could not invite")
pending = h.transports.fetch("Carol").pending_invitations
assert(pending.length == 1 && pending.first["sender"] == "Bob", "guest invitation was not delivered")
accepted = h.transports.fetch("Carol").establish_membership(table_id: h.table["__id"], owner: "Alice",
  capacity: 8, user: "Carol", table: h.table, invitation_id: pending.first["__id"])
assert(accepted && h.core.participants.length == 3, "invited guest did not join")
assert(h.transports.fetch("Carol").pending_invitations.empty?, "accepted invitation is still pending")

# Failure (including uncertain delivery) must release the duplicate reservation.
[false, EltenAPI::LiveSessions::TimeoutError.new("lost reply")].each do |failure|
  begin
    result = invitations.deliver(table: h.table, sender: "Bob", recipient: "Dave") do
      raise failure if failure.is_a?(Exception)
      failure
    end
    assert(result == nil, "failed invitation was reported as sent")
  rescue EltenAPI::LiveSessions::TimeoutError
  end
  retry_result = invitations.deliver(table: h.table, sender: "Bob", recipient: "Dave") { false }
  assert(retry_result == nil, "failed invitation kept a ten-minute duplicate lock")
end
sent = invitations.deliver(table: h.table, sender: "Bob", recipient: "Dave") { true }
assert(sent.created?, "failed attempts prevented a later delivery")
duplicate = invitations.deliver(table: h.table, sender: "Bob", recipient: "Dave") { raise "duplicate was sent" }
assert(!duplicate.created?, "a successful invitation lost duplicate protection")

# Invitation and public join must both count computers, not just live humans.
[:invitation, :discovery].each do |path|
  full = NativeRoomHarness.new(users: ["Alice"])
  full.add_client("Bob")
  owner = full.transports.fetch("Alice")
  owner.invite_user(table_id: full.table["__id"], user: "Bob", metadata: { "invitation_id" => 123 })
  owner.update_room(full.table, { "bot_count" => 7 }, actor: "Alice")
  recipient = full.transports.fetch("Bob")
  joined = if path == :invitation
    recipient.establish_membership(table_id: full.table["__id"], owner: "Alice", capacity: 8,
      user: "Bob", table: full.table, invitation_id: 123)
  else
    full.join("Bob")
  end
  assert(!joined, "#{path} admitted a ninth human/bot participant")
  assert(full.core.participants.values.map(&:user) == ["Alice"], "#{path} left a rejected membership behind")
  assert(recipient.current_room("Bob") == nil, "#{path} left a rejected current room")
end

h.transports.fetch("Alice").deactivate_table(table_id: h.table["__id"])
assert(h.transports.fetch("Bob").consume_recovery(h.table["__id"]), "remote closure did not notify the client")
assert(h.transports.fetch("Bob").room_snapshot(h.table) == nil, "remote closure left an active room")
assert(h.transports.fetch("Bob").discover_rooms.empty?, "closed room is discoverable")
puts "Native transport tests passed: public joins, guest invitations, failure rollback, capacity and closure"
