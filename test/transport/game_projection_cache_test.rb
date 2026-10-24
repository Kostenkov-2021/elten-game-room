require_relative '../support/native_room_harness'
require_relative '../../games/tic_tac_toe'
include GameRoomTest::Assertions

h = NativeRoomHarness.new(game: GameRoomGames::TicTacToe.new, users: %w[Alice Bob])
h.start
h.submit('Alice', h.game.legal_actions(h.replay('Alice'), 'Alice').first)
store = h.transports['Alice'].instance_variable_get(:@live_store)
repo = h.repositories['Alice']
expansions = 0
original = store.method(:expand_game_action)
store.define_singleton_method(:expand_game_action) do |*args, **kw|
  expansions += 1
  original.call(*args, **kw)
end
first = repo.snapshot_for(h.session, read_only: true)
before = expansions
20.times do
  same = repo.snapshot_for(h.session, read_only: true)
  assert(same.events.equal?(first.events), 'Unchanged log was materialized again')
end
assert_equal(before, expansions, 'Repeated read expanded an old action')
mutable = repo.snapshot_for(h.session)
mutable.events.first['value'].replace('local edit')
assert(first.events.first['value'] != 'local edit', 'Ordinary mutable snapshot leaked into the retained log')
h.submit('Bob', h.game.legal_actions(h.replay('Bob'), 'Bob').first)
before = expansions
second = repo.snapshot_for(h.session, read_only: true)
assert_equal(2, second.events.size)
assert(second.events.first.equal?(first.events.first), 'An appended move rebuilt the earlier record')
assert_equal(1, expansions-before, 'An append expanded something other than its new row')
assert_equal(h.events('Bob'), second.events)

# A delayed native timestamp correction changes the same count/ID prefix.
row = store.instance_variable_get(:@rooms).fetch(h.table['__id']).records.find { |item| item.packet['kind']=='game_action' }
row.estimated_time = true
old_time = row.created_at
store.send(:ingest_record, h.table['__id'], sequence: row.sequence, message_id: row.message_id,
  sender: row.sender, packet: row.packet, created_at: old_time+7)
corrected = repo.snapshot_for(h.session, read_only: true)
assert_equal(old_time+7, corrected.events.first['created_at'])
assert_equal(old_time, first.events.first['created_at'])
assert_equal(2, corrected.events.size)

# Native metadata participates in validation even with the same generation.
# An ordinary session cannot silently become a private-hand session while an
# old public projection remains cached.
native=store.instance_variable_get(:@sessions).fetch(h.table['__id'])
original_metadata=native.metadata
native.define_singleton_method(:metadata) { original_metadata.merge('owner'=>'Mallory') }
changed=repo.snapshot_for(h.session,read_only:true)
assert(changed.events.empty?, 'Changed native authentication reused a stale public projection')
native.define_singleton_method(:metadata) { original_metadata }
assert_equal(corrected.events, repo.snapshot_for(h.session,read_only:true).events)

# A racing read cannot publish its old prefix under the newly observed generation.
original_read = store.method(:records_for)
injected = false
store.define_singleton_method(:records_for) do |id, **options|
  result = original_read.call(id, **options)
  unless injected
    injected = true
    room = instance_variable_get(:@rooms).fetch(id)
    room.record_generation += 1
    room.records = room.records.dup
  end
  result
end
repo.snapshot_for(h.session, read_only: true)
room = store.instance_variable_get(:@rooms).fetch(h.table['__id'])
assert(!room.game_projection || room.game_projection[:source].equal?(room.records), 'Old collection published into replacement state')
puts 'PASS public projection cache: unchanged reads, append-only reuse, mutable isolation, timestamp corrections, both clients and collection replacement'
