require_relative "../support/native_live_sessions"
broker = NativeLiveSessionsBroker.new
$game_room_test_user = 'Alice'
alice = GameRoomTransport.new(ProgramDouble.new(broker.endpoint('Alice')))
bob = GameRoomTransport.new(ProgramDouble.new(broker.endpoint('Bob')))
table = alice.create_room(name:'Test', game:'farkle', owner:'Alice', game_options:'{}')
bob.join_room(bob.discover_rooms.first, 'Bob')
native = broker.cores.values.first.views.find { |view| view.user == 'Alice' }
transfer = native.method(:transfer_ownership)
calls = 0
native.define_singleton_method(:transfer_ownership) do |target|
  calls += 1
  transfer.call(target)
  raise EltenAPI::LiveSessions::TimeoutError, 'lost reply after transfer'
end
assert(alice.transfer_room_owner(table,'Bob'), 'Confirmed native event ignored after lost transfer reply')
assert(calls == 1 && !native.owner?, 'Transfer was repeated or rolled back')
$game_room_test_user = 'Bob'
view = broker.cores.values.first.views.find { |v| v.user == 'Bob' }
update = view.method(:update_discovery_metadata)
view.define_singleton_method(:update_discovery_metadata) do |metadata, **options|
  update.call(metadata, **options)
  raise EltenAPI::LiveSessions::TimeoutError, 'lost reply after anchor'
end
room = bob.room_snapshot(table)
assert(room[:table]['owner'] == 'Bob', 'Confirmed anchor ignored after lost reply')
store = bob.instance_variable_get(:@live_store)
assert(store.send(:control_ledger,table['__id']).complete, 'Confirmed chain not readable')
original_anchor = view.discovery_metadata['control_anchor']
3.times { bob.room_snapshot(table) }
assert(view.discovery_metadata['control_anchor'] == original_anchor, 'Uncertain transfer generated repeated ownership records')
view.define_singleton_method(:update_discovery_metadata) { |*args, **options| update.call(*args, **options) }
repo = GameRepository.new(ProgramDouble.new(broker.endpoint('Bob')), transport:bob,server_tables:Object.new)
session = repo.start_session(table:room[:table],game:'farkle',players:%w[Alice Bob])
view.define_singleton_method(:update_discovery_metadata) { |*_args, **_options| raise EltenAPI::LiveSessions::TimeoutError, 'before anchor' }
begin
  bob.set_seat_controller(table,session_id:session['__id'],seat:'Alice',bot:true)
  raise 'Unconfirmed control returned success'
rescue EltenAPI::LiveSessions::TimeoutError
end
assert(repo.session_for_table(table)['__players'] == %w[Alice Bob], 'Unanchored orphan gained authority')
view.define_singleton_method(:update_discovery_metadata) { |*args, **options| update.call(*args, **options) }
assert(bob.set_seat_controller(table,session_id:session['__id'],seat:'alice',bot:true), 'Could not retry after failed anchor')
assert(GameRoomParticipants.bot?(repo.session_for_table(table)['__players'].first) && repo.session_for_table(table)['__players'].length == 2, 'Case variation created an extra seat')
puts 'Lost replies and uncommitted control records: OK'
