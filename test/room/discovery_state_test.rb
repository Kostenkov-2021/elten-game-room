require_relative "../support/native_live_sessions"

broker = NativeLiveSessionsBroker.new
lobbies = %w[Alice Bob Carol].to_h do |name|
  program = ProgramDouble.new(broker.endpoint(name))
  transport = GameRoomTransport.new(program)
  [name, LobbyRepository.new(program, transport: transport, server_tables: Object.new)]
end
$game_room_test_user = "Alice"
alice = lobbies.fetch("Alice")
table = alice.create_table(name: "Discovery regression", game: "farkle", owner: "Alice", bot_count: 7).table
assert(lobbies.fetch("Bob").open_table_snapshots.first.participant_count == 8, "creation must include seven bots")
transport = alice.instance_variable_get(:@transport)
transport.update_room(table, {"status" => "playing"}, actor: "Alice")
remote = lobbies.fetch("Bob").open_table_snapshots.first
assert(remote.table["status"] == "playing" && remote.participant_count == 8, "discovery must show the running full game")
$game_room_test_user = "Bob"
assert(lobbies.fetch("Bob").join_table(remote.table, "Bob").status == :full, "full must not become closed or transport_failed")
$game_room_test_user = "Alice"
transport.update_room(table, {"bot_count" => 0, "bot_names" => []}, actor: "Alice")
$game_room_test_user = "Bob"
bob_table = lobbies.fetch("Bob").open_tables.first
assert(lobbies.fetch("Bob").join_table(bob_table, "Bob").entered?, "join after removing bots")
bob_transport = lobbies.fetch("Bob").instance_variable_get(:@transport)
bob_transport.set_observer(table, true, actor: "Bob")
$game_room_test_user = "Alice"
snapshot = alice.snapshot_for(table)
assert(snapshot.participant_count == 1 && snapshot.members.length == 2, "observer occupies native membership, not a player seat")
remote = lobbies.fetch("Carol").open_table_snapshots.first
assert(remote.participant_count == 1 && remote.table["__native_participant_count"] == 2, "remote description must distinguish players from members")
view = broker.cores.values.first.views.find { |v| v.user == "Alice" }
before = view.calls[:discovery_update]
20.times { alice.snapshot_for(table) }
assert(view.calls[:discovery_update] == before, "unchanged snapshots must not send updates")
assert(broker.cores.values.first.visibility == :public, "metadata must not change visibility")

# Failed publication cannot roll back the actual room or generate duplicate
# writes on every snapshot. The normal later snapshot retries after backoff.
original_update = view.method(:update_discovery_metadata)
failures = 0
view.define_singleton_method(:update_discovery_metadata) do |*_args, **_kwargs|
  failures += 1
  raise EltenAPI::LiveSessions::TimeoutError, 'publication timed out'
end
transport.update_room(table, {'status'=>'waiting'}, actor: 'Alice')
assert(alice.snapshot_for(table).table['status'] == 'waiting', 'Publication failure rolled back committed room state')
20.times { alice.snapshot_for(table) }
assert(failures == 1, 'Failed publication was retried without backoff')
view.define_singleton_method(:update_discovery_metadata, original_update)
store = transport.instance_variable_get(:@live_store)
store.instance_variable_get(:@discovery_retry_at)[table['__id']] = 0
alice.snapshot_for(table)
assert(lobbies.fetch('Carol').open_table_snapshots.first.table['status'] == 'waiting', 'Normal later snapshot did not recover publication')

# Native membership capacity (including observers) is distinct from seats.
small = NativeLiveSessionsBroker.new
owner = GameRoomTransport.new(ProgramDouble.new(small.endpoint('Alice')))
guest = GameRoomTransport.new(ProgramDouble.new(small.endpoint('Bob')))
next_guest = GameRoomTransport.new(ProgramDouble.new(small.endpoint('Carol')))
room = owner.create_room(name: 'Two memberships', game: 'chess', owner: 'Alice', game_options: '{}', capacity: 2)
assert(guest.join_room(guest.discover_rooms.first, 'Bob') == :joined, 'Could not fill native capacity')
stale = next_guest.discover_rooms.first
assert(!stale['__discovered_session'].can_join?, 'Fixture is not a stale full listing')
guest.deactivate_table(table_id: room['__id'])
assert(next_guest.join_room(stale, 'Carol') == :joined, 'Stale full description prevented an actually available join')
owner.deactivate_table(table_id: room['__id'])
assert(guest.join_room(stale, 'Bob') == :closed, 'Closed native session became a generic network failure')
puts "Discovery state: bot count, playing status, observers, full reason and deduplicated updates passed"
