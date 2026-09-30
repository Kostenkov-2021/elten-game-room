require_relative "../support/native_live_sessions"

$game_room_test_user = 'Alice'
broker = NativeLiveSessionsBroker.new
owner = GameRoomTransport.new(ProgramDouble.new(broker.endpoint('Alice')))
reader_endpoint = broker.endpoint('Reader')
reader = GameRoomTransport.new(ProgramDouble.new(reader_endpoint))
105.times do |index|
  owner.create_room(name: "Discovery #{index}", game: 'test', owner: 'Alice', game_options: '{}', capacity: 8)
end
rows = reader.discover_rooms
store = reader.instance_variable_get(:@live_store)
assert(rows.length == 105, 'discovery cache limit truncated visible rooms')
assert(store.instance_variable_get(:@discovered).length == 100, 'discovery cache is not capped at100 unprotected items')
uncached = rows.find { |row| !store.instance_variable_get(:@discovered).key?(row['__id']) }
assert(uncached && reader.join_room(uncached, 'Reader') == :joined, 'evicted discovery item lost explicit join handle')
snapshot = store.instance_variable_get(:@discovered).dup
reader_endpoint.define_singleton_method(:discover_sessions) { |**_| raise IOError, 'discovery unavailable' }
begin
  reader.discover_rooms
  raise 'discovery failure hidden'
rescue IOError
end
assert(store.instance_variable_get(:@discovered) == snapshot, 'failed discovery erased last successful cache')

transport = GameRoomTransport.new(Object.new)
source = transport.instance_variable_get(:@live_store)
repository = GameRepository.new(Object.new, transport: transport)
idle = repository.bot_turn_controller(1)
repository.bot_turn_controller(2)
assert(!idle.ready?(session_id: 1, actor: 'Alice') && idle.acquire(session_id: 1, actor: 'Alice', revision: [0,0]).nil?, 'retired stale reference acquired a lease')
assert(!repository.bot_turn_controller(1).equal?(idle), 'reused room did not get a fresh idle controller')
busy = repository.bot_turn_controller(3)
lease = busy.acquire(session_id: 1, actor: 'Alice', revision: [0,0])
repository.bot_turn_controller(4)
assert(repository.bot_turn_controller(3).equal?(busy) && !busy.retire_if_idle, 'thinking controller evicted')
busy.submitting(lease, events: [{'action' => 'play', 'value' => ''}])
assert(!busy.retire_if_idle, 'submitting controller retired')
busy.submission_failed(lease)
assert(!busy.retire_if_idle, 'uncertain controller retired')

# Schedule acquisition exactly before the retirement takes its own lock.
racing = repository.bot_turn_controller(5)
original = racing.method(:retire_if_idle)
race_lease = nil
racing.define_singleton_method(:retire_if_idle) do
  race_lease ||= acquire(session_id: 5, actor: 'Alice', revision: [0,0])
  original.call
end
repository.bot_turn_controller(6)
assert(race_lease && repository.bot_turn_controller(5).equal?(racing), 'retirement deleted newly acquired controller')

# Keep each non-idle source even when ordinary inactive room pressure is high.
source.send(:room_state, 10).pending_move = {uncertain: true}
source.send(:room_state, 11).recovered_moves = [:unconsumed]
source.send(:begin_room_io, 12)
lock = Mutex.new
lock.lock
source.send(:room_state, 13).control_lock = lock
feed1 = transport.subscribe_game_session(14)
feed2 = transport.subscribe_game_session(14)
source.instance_variable_get(:@mutex).synchronize do
  (10..40).each do |id|
    source.send(:room_state, id).records << :retained_marker
    source.send(:retain_inactive_room, id)
  end
end
transport.with_retained_rooms do |rooms|
  assert((10..14).all? { |id| rooms[id] }, 'pending/recovered/in-flight/control/subscription missing from retention')
end
feed1.close
assert(source.instance_variable_get(:@rooms).key?(14), 'one closed feed released another live subscription')
feed1.close
assert(source.send(:room_state, 14).subscription_count == 1, 'double close decremented another feed')
feed2.close
(source.send(:room_state, 10).pending_move = nil)
source.send(:room_state, 11).take_recovered_moves
source.send(:end_room_io, 12)
lock.unlock
source.instance_variable_get(:@mutex).synchronize do
  (41..48).each { |id| source.send(:retain_inactive_room, id) }
end
source.with_retained_rooms { |_rooms| }
assert((10..14).none? { |id| source.instance_variable_get(:@rooms).key?(id) }, 'completed protections did not release old inactive data')

# A dependent cleanup cannot use a snapshot while a new membership is being
# attached. The new callback must remain visible after the critical section.
native = Struct.new(:id, :metadata, :discovery_metadata) do
  def closed?; false; end
end.new('concurrent-native', {'owner' => 'Alice'}, {})
entered = Queue.new
worker = nil
transport.with_retained_rooms do |rooms|
  assert(source.instance_variable_get(:@mutex).owned? && !rooms[99], 'retention snapshot lost its atomic store boundary')
  worker = Thread.new do
    entered << true
    source.send(:attach_session, 99, native)
    transport.send(:live_store_changed, 99, :table, nil)
  end
  entered.pop
end
assert(worker.join(3), 'attachment/retention lock order deadlocked')
worker.value
assert(source.active_membership?(99) && transport.consume_table_change(99), 'concurrent attachment lost its notification to stale cleanup')
puts 'Retention boundaries: discovery100 vs visible105, failed refresh, explicit join, retired reference/race, all pending protections and feed refcounts OK'
