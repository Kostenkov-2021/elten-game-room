require_relative "../support/assertions"
require_relative "../../lib/game_event_protocol"
require_relative "../../games/contracts"
include GameRoomTest::Assertions

codec = GameRoomEventProtocol
valid = {'action' => 'a' * 32, 'value' => 'ą' * 64, 'move_id' => 'receipt'}
assert(codec.valid_wire_commands?([valid] * 50), 'boundary command rejected')
assert(!codec.valid_wire_commands?([valid] * 51), 'oversized batch accepted')
assert(!codec.valid_wire_commands?([]), 'empty batch accepted')
%w[action value].each do |field|
  assert(!codec.valid_wire_commands?([valid.merge(field => valid[field] + 'x')]), "oversized #{field} accepted")
  assert(!codec.valid_wire_commands?([valid.merge(field => 3)]), "remote #{field} coerced")
end
assert(!codec.valid_wire_commands?([valid.merge('move_id' => '')]), 'missing identity accepted')
assert(codec.valid_wire_command?(valid.reject { |key, _| key == 'move_id' }), 'archived command requires live receipt')
[GameRoomGames::EventCommand.new(action: 'play', value: 'AS'), {action: 'play', value: 'AS'}, {'action' => 'play', 'value' => 'AS'}].each do |command|
  assert_equal({'action' => 'play', 'value' => 'AS'}, codec.normalized(command))
end
assert_raises(ArgumentError) { codec.validate_commands!([valid] * 51) }
assert_equal(valid['value'], codec.normalized(valid)['value'])
assert_equal(Encoding::UTF_8, codec.normalized(valid)['value'].encoding)
puts 'PASS event dialect: local adapters, independent wire validation and unchanged text limits'
