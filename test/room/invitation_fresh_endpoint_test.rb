require_relative "../support/invitation_fresh_endpoint"

broker = NativeLiveSessionsBroker.new
gateway = DurableNoticeGateway.new
alice = InvitationAppDriver.new(broker, "Alice", gateway)
$game_room_test_user = "Alice"
table = alice.transport.create_room(name: "Public", game: "makao", owner: "Alice", game_options: "{}")
result = alice.send(:deliver_table_invitation, table, "Bob")
assert(result.created?, "public app notification was not sent")
assert(broker.endpoint("Bob").next_invitation == nil, "public room unnecessarily sent a native invitation")
assert(alice.sent.last[2] == 300, "public notification does not last five minutes")
bob = InvitationAppDriver.new(broker, "Bob", gateway, fresh: true)
$game_room_test_user = "Bob"
pending = bob.send(:load_pending_invitations)
assert(pending.length == 1 && bob.transport.pending_invitations.empty?, "fresh endpoint depended on an old native invitation queue")
assert(bob.send(:accept_pending_invitation, pending.first[:invitation]) != nil, "fresh program did not accept public notification: #{bob.errors}")
assert(gateway.rows["Bob"].all?(&:revoked), "successful notification join did not clear same-table invitations")
$game_room_test_user = "Alice"
assert(alice.send(:deliver_table_invitation, table, "Bob").created?, "accepted invitation kept sender duplicate lock")
# Entering manually also resolves every invitation to this table, not another.
other = alice.transport.create_room(name: "Other", game: "makao", owner: "Alice", game_options: "{}")
other_notice = gateway.send("Bob", alice.send(:invitation_metadata, other, 555))
$game_room_test_user = "Bob"
assert(bob.send(:join_table_snapshot, bob.send(:load_pending_invitations).find { |choice| choice[:invitation].table_id == table["__id"] }[:snapshot]).entered?, "manual join could not settle invitations")
assert(!other_notice.revoked, "join cleared an invitation to a different table")

$game_room_test_user = "Alice"
private_room = alice.transport.create_room(name: "Private", game: "makao", owner: "Alice", game_options: "{}", private_table: true)
# Model the server's actual shorter TTL: no invented TTL argument to invite.
private_view = broker.endpoint("Alice").sessions.find { |view| view.id == private_room["__live_session_id"] }
private_view.define_singleton_method(:invite) do |user, metadata:|
  result = super(user, metadata: metadata)
  @core.invitations[user.downcase] = Time.now.to_i + 120
  result["expires_at"] = @core.invitations[user.downcase]
  result
end
assert(alice.send(:deliver_table_invitation, private_room, "Carol", continuation: true).created?, "private invitation was not sent")
assert(alice.sent.last[2] == 120 && alice.sent.last[1]["expires_at"] == Time.now.to_i + 120, "private app notice disagrees with server expiry")
carol = InvitationAppDriver.new(broker, "Carol", gateway, fresh: true)
$game_room_test_user = "Carol"
pending = carol.send(:load_pending_invitations).first[:invitation]
assert(carol.transport.pending_invitations.empty?, "private test must use an empty endpoint queue")
assert(carol.send(:reject_pending_invitation, pending), "fresh private rejection failed: #{carol.errors}")
assert(carol.transport.discover_rooms(include_private: true).none? { |row| row["__id"] == private_room["__id"] }, "rejected private invitation still grants discovery permission")
$game_room_test_user = "Alice"
assert(alice.send(:deliver_table_invitation, private_room, "Carol").created?, "private rejection kept sender duplicate lock")
$game_room_test_user = "Carol"
pending = carol.send(:load_pending_invitations).first[:invitation]
assert(carol.send(:accept_pending_invitation, pending), "private acceptance did not use fresh server discovery")
assert(carol.transport.discover_rooms.none? { |row| row["__id"] == private_room["__id"] }, "private room leaked after joining")

$game_room_test_user = "Alice"
full = alice.transport.create_room(name: "Full with bots", game: "makao", owner: "Alice", game_options: "{}", bot_count: 7)
alice.send(:deliver_table_invitation, full, "Dave")
dave = InvitationAppDriver.new(broker, "Dave", gateway, fresh: true)
$game_room_test_user = "Dave"
pending = dave.send(:load_pending_invitations).first[:invitation]
assert(dave.send(:accept_pending_invitation, pending) == nil && dave.alerts.last == "This table is full.", "bots/full room was misreported as expired/network error")
assert(!gateway.rows["Dave"].first.revoked, "full table destroyed a still-valid invitation")
gateway.error = EltenAPI::LiveSessions::TimeoutError.new("offline")
assert(dave.send(:accept_pending_invitation, pending) == nil, "network failure was treated as acceptance")
assert(!gateway.rows["Dave"].first.revoked, "network failure revoked a valid invitation")
gateway.error = nil
pending.invitation["expires_at"] = Time.now.to_i - 1
assert(dave.send(:accept_pending_invitation, pending) == nil && dave.alerts.last == "This invitation has expired.", "expired invitation was not distinguished")
assert(gateway.rows["Dave"].first.revoked, "expired invitation was not cleaned up")
$game_room_test_user = "Alice"
private_view.define_singleton_method(:invite) { |user, metadata:| super(user, metadata: metadata).reject { |key, _value| key == "expires_at" } }
assert(alice.run_network_task("invite") { alice.send(:deliver_table_invitation, private_room, "Eve") } == nil, "missing server expiry was silently invented")
assert(alice.errors.last.is_a?(GameRoomNetworkErrors::UnsupportedInvitation), "unsupported API response escaped the network boundary")
assert(GameRoomNetworkErrors.expected?(alice.errors.last) && !GameRoomNetworkErrors.transient?(alice.errors.last), "capability mismatch is not a handled non-transient failure")
assert(gateway.rows["Eve"].empty?, "unverifiable private expiration produced a notification")
assert(alice.instance_variable_get(:@invitations).create(table: private_room, sender: "Alice", recipient: "Eve").created?, "failed invitation kept duplicate lock")
puts "Fresh public/private notifications, manual joins, sender resolution, TTL, full room and network failure: OK"
