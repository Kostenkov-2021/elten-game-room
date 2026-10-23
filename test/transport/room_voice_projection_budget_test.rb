require_relative '../support/native_room_harness'

h = NativeRoomHarness.new(users: %w[Alice Bob])
transport = h.transports.fetch('Alice')
table = h.table
24.times do |index|
  user = index < 12 ? 'Alice' : 'Bob'
  if index == 12
    h.as('Alice') { transport.transfer_room_owner(table, 'Bob') }
  end
  writer = h.transports.fetch(user)
  h.as(user) do
    previous = writer.table_voice(table).fetch('head')
    claim = writer.change_table_voice(table, {'operation'=>'claim', 'previous'=>previous}, actor:user)
    assert(claim[:accepted], 'fixture claim failed')
    published = writer.change_table_voice(table, {'operation'=>'publish', 'previous'=>claim[:voice]['head'],
      'channel_id'=>index+1, 'name'=>"Conversation #{index}", 'password'=>"private #{index}"}, actor:user)
    assert(published[:accepted], 'fixture publish failed')
    # Keep the last published conference, including its member-only secret.
    unless index == 23
      cleared = writer.change_table_voice(table, {'operation'=>'clear', 'previous'=>published[:voice]['head']}, actor:user)
      assert(cleared[:accepted], 'fixture clear failed')
    end
  end
end

store = transport.instance_variable_get(:@live_store)
id = table.fetch('__id')
records = store.send(:records_for, id)
base = store.send(:table_from_metadata, h.view('Alice').metadata, id)
expected = store.send(:project_room_records, id, base.dup, records:records)
calls = 0
original = store.method(:control_ledger)
store.define_singleton_method(:control_ledger) do |*args, **options|
  calls += 1
  original.call(*args, **options)
end
actual = store.send(:project_room_records, id, base.dup, records:records)
assert_equal(expected, actual, 'shared authority lookup changed the room projection')
assert_equal('Bob', actual.first.fetch('voice').fetch('creator'))
assert_equal('private 23', actual.first.fetch('voice').fetch('password'))
assert_equal(1, calls, 'room projection rebuilt the control ledger for each conference event')
calls = 0
store.send(:project_room_records, id, base.dup, records:[])
assert_equal(0, calls, 'rooms without voice events acquired a new authority lookup')
puts 'PASS room voice projection: one authority ledger, historical owners, identical member-only state and no empty-room overhead'
