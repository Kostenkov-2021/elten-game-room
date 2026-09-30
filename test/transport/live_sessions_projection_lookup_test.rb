require_relative '../support/native_room_harness'

h = NativeRoomHarness.new(users: %w[Alice Bob])
transport = h.transports.fetch('Alice')
repository = h.repositories.fetch('Alice')
store = transport.instance_variable_get(:@live_store)
identifier = 1000
store.define_singleton_method(:unused_game_identifier) { |_table| identifier -= 1 }
sessions = Array.new(12) { h.start }
expected = transport.game_sessions(h.table)
assert(sessions.last['__id'] < sessions.first['__id'], 'Fixture must reverse chronological ID order')

materialized = []
original = store.method(:game_session_from)
store.define_singleton_method(:game_session_from) do |record|
  materialized << record.packet.dig('data', 'session_id')
  original.call(record)
end
sessions.each do |session|
  materialized.clear
  found = transport.game_session(session['__id'], table: h.table)
  assert(found == expected.find { |row| row['__id'] == session['__id'] }, 'Targeted lookup changed projection')
  assert(materialized == [session['__id']], 'Single-session lookup materialized unrelated matches')
end
materialized.clear
assert(transport.game_session(987654, table: h.table) == nil, 'Unknown session found')
assert(materialized.empty?, 'Unknown ID materialized unrelated matches')
materialized.clear
assert(repository.session_for_table(h.table) == expected.last(12).max_by { |row| row['__stack_sequence'] }, 'Latest valid match changed')
assert(materialized == [sessions.last['__id']], 'Current-session lookup materialized old matches')
materialized.clear
assert(repository.latest_session_id_for_table(h.table) == sessions.last['__id'], 'Random ID replaced stack order')
assert(materialized == [sessions.last['__id']], 'Latest ID lookup materialized old matches')
materialized.clear
snapshot = repository.snapshot_for(sessions.last)
assert(snapshot.session['__id'] == sessions.last['__id'], 'Snapshot selected another match')
assert(materialized == [sessions.last['__id']] * 2, 'Snapshot must recheck its boundary without rebuilding old matches')

# A boundary arriving during event retrieval must still affect that snapshot.
events = transport.method(:game_events)
freeze_during_read = true
transport.define_singleton_method(:game_events) do |session, **options|
  result = events.call(session, **options)
  if freeze_during_read
    freeze_during_read = false
    h.as('Alice') { transport.freeze_game(session) }
  end
  result
end
assert(repository.snapshot_for(sessions.last).session['__frozen'], 'Snapshot missed a boundary arriving during event read')
h.as('Alice') { transport.freeze_game(sessions.last, frozen: false) }
assert(!repository.snapshot_for(sessions.last).session['__frozen'], 'Unfreeze remained stale')

# A newer row can be valid transport data but incompatible with this table.
# Repository selection must continue to the preceding compatible match.
foreign = h.as('Alice') do
  transport.start_game(table: h.table, game: 'other_game', players: h.users, options: '{}', actor: 'Alice')
end
materialized.clear
assert(repository.session_for_table(h.table)['__id'] == sessions.last['__id'], 'Selection stopped at an incompatible match')
assert(materialized == [foreign['__id'], sessions.last['__id']], 'Selection rebuilt rows after its first match')
assert(repository.latest_session_id_for_table(h.table) == foreign['__id'], 'Latest ID incorrectly applied the table compatibility filter')

# A valid start with missing archive chunks has no materializable session.
store.send(:append_record, h.table['__id'], 'game_started', {
  'session_id' => 123456, 'game' => 'test', 'players' => h.users, 'options' => '{}', 'created_at' => 1,
  'archive_id' => 'missing', 'archive_events' => 1, 'event_id_base' => 1, 'clock_offset' => 0
}, actor: 'Alice')
assert(transport.game_session(123456, table: h.table) == nil, 'Incomplete archive became visible')
assert(repository.latest_session_id_for_table(h.table) == foreign['__id'], 'Incomplete archive hid the latest complete match')
assert(repository.session_for_table(h.table)['__id'] == sessions.last['__id'], 'Incomplete archive hid the latest compatible match')

# Keep the first materializable start for a duplicated historical ID.
store.send(:append_record, h.table['__id'], 'game_started', {
  'session_id' => sessions.first['__id'], 'game' => 'other_game', 'players' => h.users,
  'options' => '{}', 'created_at' => 1
}, actor: 'Alice')
assert(transport.game_session(sessions.first['__id'], table: h.table)['game'] == 'test', 'Duplicate ID replaced its first historical start')
assert(transport.game_session(sessions.first['__id'])['game'] == 'test', 'Lookup across active tables changed duplicate semantics')
puts 'PASS targeted session projections: bounded materialization, stack order, filtering, archive gaps, duplicates and fresh boundaries'
