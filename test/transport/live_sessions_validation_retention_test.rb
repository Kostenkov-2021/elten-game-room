require_relative "../support/native_live_sessions"

# Pure validation must not obtain membership or use an unaccepted/future start.
store = GameRoomLiveSessionStore.new(Object.new)
native = Struct.new(:metadata, :discovery_metadata, :closed?) do
  def owner?; false; end
  def leave; self[:closed?] = true; end
end
def add_record(store, table, seq, kind, data, sender: 'Alice', actor: sender, id: seq.to_s)
  store.send(:ingest_record, table, sequence: seq, message_id: id, sender: sender,
    created_at: seq, packet: {'version' => 2, 'kind' => kind, 'actor' => actor, 'data' => data})
end
def start_data(id = 123)
  {'session_id' => id, 'game' => 'uno', 'options' => '{}', 'players' => %w[Alice Bob], 'created_at' => 1}
end
def action_data(id = 123)
  {'session_id' => id, 'sequence' => 0, 'events' => [{'action' => 'draw', 'value' => '', 'move_id' => 'test'}]}
end
store.instance_variable_get(:@sessions)[1] = native.new({'owner' => 'Alice'}, {}, false)
add_record(store, 1, 1, 'game_action', action_data)
add_record(store, 1, 2, 'game_started', start_data, sender: 'Mallory')
add_record(store, 1, 3, 'game_action', action_data)
add_record(store, 1, 4, 'game_started', start_data)
add_record(store, 1, 5, 'game_action', action_data, sender: 'Mallory', actor: 'Alice')
add_record(store, 1, 6, 'game_action', action_data)
assert(store.send(:records_for, 1).map(&:sequence) == [4, 6], 'Only accepted earlier start authorizes action')
add_record(store, 1, 8, 'game_action', action_data(456))
add_record(store, 1, 7, 'game_started', start_data(456))
assert(store.send(:records_for, 1).map(&:sequence) == [4, 6, 7, 8], 'Late start is ordered and revalidated')
add_record(store, 1, 9, 'game_action', action_data, id: '6')
assert(store.send(:records_for, 1).map(&:sequence) == [4, 6, 7, 8], 'Duplicate operation does not apply twice')

validator_class = GameRoomLiveSessionStore::RecordValidator
calls = 0
counter = Module.new do
  define_method(:accept) { |record, **options| calls += 1; super(record, **options) }
end
validator_class.prepend(counter)
1600.times { |i| add_record(store, 1, 10 + i, 'game_action', action_data) }
expected = store.send(:records_for, 1).map(&:sequence)
assert(calls == 1608, 'Exactly one validation per stored operation, including rejected entries')
store.send(:records_for, 1)
assert(calls == 1608, 'Unchanged generation uses verified cache')
assert(expected.size == 1604, 'Long history preserves every accepted action')

# Pending writes and in-flight recovery retain their room even under pressure.
store.send(:room_state, 1).pending_move = {uncertain: true}
store.instance_variable_get(:@sessions).delete(1)
store.instance_variable_get(:@mutex).synchronize { store.send(:retain_inactive_room, 1) }
store.send(:begin_room_io, 2)
30.times do |i|
  id = i + 2
  store.instance_variable_get(:@sessions)[id] = native.new({'owner' => 'Alice'}, {}, false)
  add_record(store, id, 1, 'game_started', start_data(id))
  store.send(:records_for, id)
  assert(store.deactivate_room(id), 'Leave works')
end
assert(store.instance_variable_get(:@rooms).key?(1), 'Uncertain write survives eviction')
assert(store.instance_variable_get(:@rooms).key?(2), 'In-flight read survives eviction')
assert(store.instance_variable_get(:@rooms).size <= 8, 'Inactive cache is bounded')
store.send(:end_room_io, 2)
(store.send(:room_state, 1).pending_move = nil)
store.instance_variable_get(:@mutex).synchronize { store.send(:retain_inactive_room, 50) }
assert(!store.instance_variable_get(:@rooms).key?(1), 'Confirmed inactive room can be evicted')
puts 'LiveSessions indexed validation and bounded retention: OK'
