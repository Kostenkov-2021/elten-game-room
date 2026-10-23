require_relative '../support/native_live_sessions'
require_relative '../../lib/game_sync'

broker = NativeLiveSessionsBroker.new
transport = GameRoomTransport.new(ProgramDouble.new(broker.endpoint('Alice')))
first, second = [41,42].map { |id| transport.subscribe_game_session(id) }
tick = 100.0
transport.define_singleton_method(:monotonic_time) { tick }
sync = GameRoomSync::Controller.new(transport: transport, table_id: 41, session_id: 71)
transport.send(:live_store_changed, 41, :game, 71)
tick = 101.0
transport.send(:live_store_changed, 41, :game, 72)
transport.send(:live_store_changed, 42, :game, 73)
tick = 102.0
transport.send(:live_store_changed, 41, :game, 70) # Late historical hint.
event = sync.next_event
assert(event&.kind == :game_changed && event.session_id == 71 && event.received_at == 100.0, 'Historical hint hid the current room wake-up or changed its first receive time')
assert(sync.next_event.nil?, 'Coalesced room wake-up was duplicated')
assert(transport.consume_game_change(73) == 101.0, 'Consuming one room removed another room or legacy hint')
assert(first.consume_room_game_change(41), 'Foreground stole the independent runner wake-up')
assert(second.consume_game_change(73), 'First-room consume touched the second independent feed')
transport.send(:live_store_changed, 41, :game, 70)
sync.update_session(74, discard_pending: true)
assert(sync.next_event.nil?, 'Verified switch left a historical hint behind')
2_000.times { |index| transport.send(:live_store_changed, 41, :game, 1000 + index) }
assert(transport.instance_variable_get(:@pending_game_changes).size == 1, 'Wake-up memory still scales with game IDs')
assert(!transport.instance_variable_defined?(:@game_change_tables), 'Unbounded per-game side index remains')
transport.send(:live_store_changed, 42, :game, 2999)
assert(transport.consume_game_change(2999).nil?, 'Ambiguous legacy ID selected an arbitrary room')
assert(transport.consume_room_game_change(41) && transport.consume_room_game_change(42), 'Ambiguous legacy lookup destroyed either room signal')
first.close
second.close
puts 'PASS bounded room wake-ups, historical/current overlap, first timestamp, independent feeds, legacy lookup and confirmed switch drain'
