require_relative "../support/native_room_harness"
require_relative "../../games/ninety_nine"

def drain_sync(sync)
  events = []
  12.times do
    event = sync.next_event
    break unless event
    events << event.kind
  end
  events
end

[false, true].each do |playing|
  [:before_join, :after_join].each do |delivery|
    h = NativeRoomHarness.new(game: GameRoomGames::NinetyNine.new, users: %w[Alice Bob])
    h.start if playing
    if playing
      h.as('Alice') { h.transports['Alice'].replace_game_player(h.table,
        session_id: h.session['__id'], player: 'Bob') }
    end
    t = h.transports['Bob']
    id = h.table['__id']
    old_feed = t.subscribe_game_session(id)
    sync = GameRoomSync::Controller.new(transport: t, table_id: id,
      session_id: h.session.to_h['__id'])
    drain_sync(sync)

    3.times do
      old = h.view('Bob')
      callbacks = old.instance_variable_get(:@closed_callbacks).dup
      old.instance_variable_set(:@closed_callbacks, []) if delivery == :after_join
      h.as('Bob') { t.deactivate_table(table_id: id) }
      if delivery == :before_join
        assert(t.instance_variable_get(:@pending_recoveries)[id] == :closed,
          'The fixture did not deliver the native leave callback')
      end
      assert(h.join('Bob'), 'Rejoin failed')
      callbacks.each { |callback| callback.call(:left) } if delivery == :after_join
      fresh = h.view('Bob')
      assert(!fresh.equal?(old) && !fresh.closed?, 'No fresh open membership')
      calls = fresh.calls.dup
      events = drain_sync(GameRoomSync::Controller.new(transport: t, table_id: id,
        session_id: h.session.to_h['__id']))
      assert(!events.include?(:closed), 'Stale closure dismissed the rejoined window')
      assert(fresh.calls == calls, 'Discarding an obsolete close caused server I/O')
      snapshot = h.as('Bob') { t.room_snapshot(h.table) }
      assert(snapshot[:members].include?('Bob'), 'Rejoin lost membership')
      if playing
        assert(snapshot[:observers].include?('Bob'), 'Replaced human did not stay an observer')
        assert(snapshot[:bots].length == 1, 'Rejoin duplicated or removed the replacement bot')
        assert(h.replay('Alice').players == h.replay('Bob').players, 'Rejoin changed the playing seats')
      end
    end
    # A feed belongs to its old runner; do not revive it with the new UI.
    assert(old_feed.consume_recovery(id) == :closed, 'Old runner was revived after its membership ended') if delivery == :before_join
    old_feed.close

    # Closing the actual current table must still close the new view. Also
    # cover reads which evict a closed native object before its callback.
    fresh = h.view('Bob')
    fresh.instance_variable_set(:@closed, true)
    store = t.instance_variable_get(:@live_store)
    assert(!store.active_membership?(id), 'Closed current membership reported active')
    fresh.instance_variable_get(:@closed_callbacks).each { |callback| callback.call(:closed) }
    assert(sync.next_event.kind == :closed, 'Actual closure after eviction was suppressed')
  end
end

h = NativeRoomHarness.new(game: GameRoomGames::NinetyNine.new, users: %w[Alice Bob])
t = h.transports['Bob']
id = h.table['__id']
t.instance_variable_get(:@pending_recoveries)[id] = IOError.new('network failure')
assert(t.consume_recovery(id).is_a?(IOError), 'Membership check swallowed a real network failure')
h.as('Bob') { t.deactivate_table(table_id: id) }
assert(t.consume_recovery(id) == :closed, 'Departure without rejoin no longer reports closure')
h.as('Alice') { h.transports['Alice'].deactivate_table(table_id: id) }
assert(h.transports['Alice'].consume_recovery(id) == :closed, 'Last owner closure was suppressed')
puts 'Rejoin: waiting/playing, observer after bot replacement, early/late closure, repeated returns and real closure: OK'
