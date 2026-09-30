require_relative "../support/native_live_sessions"
broker = NativeLiveSessionsBroker.new
make = ->(user, fresh = false) { GameRoomTransport.new(ProgramDouble.new(broker.endpoint(user, fresh: fresh))) }
alice, bob = make.call("Alice"), make.call("Bob")
$game_room_test_user = "Alice"
table = alice.create_room(name: "Private room", game: "reversi", owner: "Alice", game_options: "{}", private_table: true)
assert(table["private"] == true, "native private visibility was not kept")
assert(alice.discover_rooms.empty? && bob.discover_rooms.empty?, "private room leaked into public discovery")
assert(bob.discover_rooms(include_private: true).empty?, "uninvited account discovered private room")
alice.invite_user(table_id: table["__id"], user: "Bob", metadata: { "invitation_id" => 123 })
fresh_bob = make.call("Bob", true)
$game_room_test_user = "Bob"
assert(fresh_bob.pending_invitations.empty?, "test must use a fresh, empty invitation queue")
invited = fresh_bob.discover_rooms(include_private: true).first
assert(invited && invited["private"], "fresh invited discovery failed")
assert(fresh_bob.establish_membership(table_id: table["__id"], owner: "Alice", capacity: 8, user: "Bob", table: invited), "fresh endpoint could not join private room")
assert(fresh_bob.discover_rooms.empty?, "member's private room leaked into widget discovery")
provider = { "table_activity" => ActivityTableDouble.new }
activity = TableActivityRepository.new(server_tables: provider, transport: fresh_bob)
activity.append(table: invited, kind: "joined", actor: "Bob")
assert(provider["table_activity"].calls.empty?, "private join was written to global lobby history")
assert(activity.entries_for(invited).any? { |item| item.kind == "joined" }, "private room lost local activity")
puts "Private tables and fresh invited discovery: OK"
