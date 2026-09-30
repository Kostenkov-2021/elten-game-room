require_relative '../support/native_room_harness'
require_relative '../../games/ninety_nine'

h = NativeRoomHarness.new(game: GameRoomGames::NinetyNine.new, users: %w[Alice Bob])
counts = Hash.new(0)
h.transports.each do |user, transport|
  listener = Object.new
  listener.define_singleton_method(:changed) { counts[user] += 1 }
  transport.presence_listener = listener
end
h.start
assert(counts.values.all? { |n| n > 0 }, 'Accepted start did not notify presence')
counts.clear
context = GameRoomGames::ActionContext.new(session_id: h.session['__id'], table_id: h.table['__id'],
  random_source: GameRoomRandom::SeededSource.new(19), now: 1000)
h.submit('Alice', {'kind' => 'command', 'action' => 'deal'}, context: context)
actor = h.replay('Alice').current_player
h.submit(actor, h.game.legal_actions(h.replay(actor), actor).first)
assert(counts.empty?, 'Cards/moves woke presence')
# Exercise all record classifications with the production callback, including
# realtime point commits; no network or additional polling is installed.
store = h.transports['Alice'].instance_variable_get(:@live_store)
record = Struct.new(:packet)
%w[activity game_action game_boundary].each do |kind|
  store.send(:emit_record_change, h.table['__id'], record.new({'kind' => kind, 'data' => {}}))
end
assert(counts.empty?, 'Chat or points woke presence')
%w[room_created room_state game_started].each do |kind|
  previous = counts['Alice']
  store.send(:emit_record_change, h.table['__id'], record.new({'kind' => kind, 'data' => {}}))
  assert(counts['Alice'] == previous + 1, "Room lifecycle #{kind} lost presence wakeup")
end
counts.clear
h.as('Bob') { h.transports['Bob'].deactivate_table(table_id: h.table['__id']) }
assert(counts['Alice'] > 0 && counts['Bob'] > 0, 'Departure did not notify both peers')
counts.clear
assert(h.join('Bob'), 'Native return failed')
assert(counts['Alice'] > 0 && counts['Bob'] > 0, 'Return did not notify both peers')
puts 'PASS presence lifecycle hooks; actions/chat/points remain silent'
