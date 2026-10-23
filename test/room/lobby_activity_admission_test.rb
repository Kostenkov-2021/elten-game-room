require_relative '../support/settings_widget'
require_relative '../support/native_background_capacity'
include GameRoomTest::Assertions

GameRoomTest::NativeBackgroundCapacity.with(128) do |work, free_capacity, _runtime|
  app = EltenGameRoom.allocate
  app.instance_variable_set(:@server_tables, Struct.new(:available?).new(true))
  app.instance_variable_set(:@lobby_activity_work, work)
  now, owner = 100.0, Thread.current
  app.define_singleton_method(:monotonic_time) { now }
  app.define_singleton_method(:run_network_task) { |*| raise 'Lobby admission used a modal task' }
  app.define_singleton_method(:game_room_settings) { {} }
  calls = []
  entry = Struct.new(:id).new(1)
  repository = Object.new
  repository.define_singleton_method(:global_entries) do
    raise 'History read on the UI thread' if Thread.current == owner
    calls << :entries
    [entry]
  end
  repository.define_singleton_method(:latest_global_id) { calls << :latest; 1 }
  app.instance_variable_set(:@table_activity, repository)
  displayed = []
  history = Object.new
  history.define_singleton_method(:replace_entries) do |items|
    assert_equal(owner, Thread.current, 'History presentation left the UI thread')
    displayed << items
  end
  3.times { assert_equal(false, app.send(:poll_lobby_activity, nil, history)) }
  assert_equal([], calls, 'Full native4+128 capacity was bypassed')
  assert_equal(nil, app.instance_variable_get(:@last_lobby_activity_poll_at), 'Refusal consumed the initial refresh')
  assert_equal(nil, app.instance_variable_get(:@last_seen_lobby_activity_id))
  free_capacity.call
  app.send(:poll_lobby_activity, nil, history)
  wait_background_work(work)
  app.send(:poll_lobby_activity, nil, history)
  assert_equal([:entries], calls, 'Initial refresh was lost or repeated')
  assert_equal([[]], displayed, 'Old lobby history was replayed after waiting for capacity')
  assert_equal(1, app.instance_variable_get(:@last_seen_lobby_activity_id))
  3.times { app.send(:poll_lobby_activity, nil, history) }
  assert_equal([:entries], calls, 'Completion bypassed the normal polling interval')
  now += EltenGameRoom::LOBBY_ACTIVITY_POLL_INTERVAL
  app.send(:poll_lobby_activity, nil, history)
  wait_background_work(work)
  app.send(:poll_lobby_activity, nil, history)
  assert_equal([:entries, :latest], calls)
end
puts 'PASS lobby activity native4+128 refusal retains initial refresh, then one background baseline and normal polling interval'
