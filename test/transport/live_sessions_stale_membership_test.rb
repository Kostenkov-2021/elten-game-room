require_relative "../support/native_room_harness"
require_relative "../../games/ninety_nine"

h = NativeRoomHarness.new(game: GameRoomGames::NinetyNine.new, users: %w[Alice Bob])
h.start
store = h.transports['Bob'].instance_variable_get(:@live_store)
old = h.view('Bob')
fresh = h.broker.endpoint('Bob', fresh: true).add_view(h.core)
store.send(:attach_session, h.table['__id'], fresh)
notices = []
store.instance_variable_set(:@changed, ->(*event) { notices << event })
store.send(:room_state, h.table['__id']).pending_move = :pending_test
old.instance_variable_get(:@closed_callbacks).each { |callback| callback.call(:replaced) }
assert(notices.none? { |event| event[1] == :closed }, 'An obsolete membership closed the current table window')
assert(store.send(:room_state, h.table['__id']).pending_move == :pending_test, 'An obsolete membership cleared the current pending action')
assert(store.instance_variable_get(:@native_session_ids)[fresh.id] == h.table['__id'], 'Obsolete callback removed the new native mapping')
assert(store.send(:active_session, h.table['__id']).equal?(fresh), 'New membership was removed')
assert(h.core.participants.key?('bob'), 'Test lost actual membership')

fresh.instance_variable_set(:@closed, true)
# A read can notice closure and evict the membership before the queued
# callback is dispatched. This is still a real closure, not a stale one.
assert(store.send(:active_session, h.table['__id']) == nil, 'Closed native membership is still active')
fresh.instance_variable_get(:@closed_callbacks).each { |callback| callback.call(:closed) }
assert(notices.count { |event| event[1] == :closed } == 1, 'Actual current membership closure was not reported')
assert(!store.send(:room_state, h.table['__id']).pending_move, 'Current membership closure retained pending actions')
puts 'Stale native membership closure cannot close the replacement table view or erase its pending action: OK'
