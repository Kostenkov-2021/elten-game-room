require_relative "../support/assertions"
require_relative "../../lib/game_session_contracts"
require_relative "../../lib/game_snapshot"
include GameRoomTest::Assertions

contracts = GameRoomSessionContracts
pair = [7, 901]
revision = contracts::EventRevision.from_legacy(pair)
assert_equal(pair, revision.to_legacy)
pair[0] = 99
assert_equal(7, revision.event_count, 'revision aliases a mutable legacy pair')
assert(revision.frozen?, 'revision must be a value')
row = {'table_id' => 3, '__id' => 10, '__control_epoch' => 'epoch-a'}
identity = contracts::SessionIdentity.from_row(row)
%w[table_id __id __control_epoch].each do |key|
  other = row.merge(key => (key == '__control_epoch' ? 'epoch-b' : 11))
  assert(identity != contracts::SessionIdentity.from_row(other), "identity ignores #{key}")
end
pending = contracts::PendingWrite.new(message_id: 'id', packet: {'events' => []}, sender: 'Alice', writing: false)
pending[:uncertain] = true
copy = GameRoomSnapshot.copy(pending)
copy.packet['events'] << 'other'
assert(pending.packet['events'].empty? && copy.uncertain, 'pending write lost copy/adapter semantics')
assert_equal(%i[table members bots observers], contracts::RoomSnapshot.new.to_h.keys)
puts 'PASS named session contracts and legacy adapters'
