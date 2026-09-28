require 'timeout'
require_relative 'support/settings_widget'

app = EltenGameRoom.allocate
app.instance_variable_set(:@server_tables, Struct.new(:available?).new(true))
now = 100.0
app.define_singleton_method(:monotonic_time) { now }
app.define_singleton_method(:run_network_task) { |*| raise 'Lobby used a modal network task' }
app.define_singleton_method(:game_room_settings) { {} }
app.define_singleton_method(:lobby_announcement_enabled?) { |*| true }
app.define_singleton_method(:game_name) { |id| id }
EltenGameRoom.define_singleton_method(:table_watch_receiver) { Struct.new(:games).new([]) }
received, release = Queue.new, Queue.new
owner = Thread.current
calls = []
entries = []
failure = nil
repository = Object.new
repository.define_singleton_method(:global_entries) do
  raise 'Network ran on UI' if Thread.current == owner
  calls << :entries
  received << true
  release.pop
  raise failure if failure
  entries.dup
end
repository.define_singleton_method(:latest_global_id) do
  raise 'Network ran on UI' if Thread.current == owner
  calls << :latest
  entries.map(&:id).max.to_i
end
repository.define_singleton_method(:text_for) { |entry, **| "event #{entry.id}" }
app.instance_variable_set(:@table_activity, repository)
history = Object.new
displayed = []
history.define_singleton_method(:replace_entries) do |items|
  assert(Thread.current == owner, 'Worker updated history')
  displayed << items
end
work = GameRoomBackground::Work.new
app.instance_variable_set(:@lobby_activity_work, work)
entry_class = Struct.new(:id, :actor, :game, :kind)
entries << entry_class.new(1, 'Bob', 'uno', 'joined')
begin
  assert(app.send(:load_lobby_history) == [], 'Initial menu requires a server result')
  Timeout.timeout(0.25) { app.send(:poll_lobby_activity, nil, history) }
  Timeout.timeout(3) { received.pop }
  100.times { app.send(:poll_lobby_activity, nil, history) }
  assert(calls == [:entries] && displayed.empty?, 'Pending history spawned duplicate work or changed UI')
  release << true
  assert(work.instance_variable_get(:@thread).join(3), 'History read did not finish')
  app.send(:poll_lobby_activity, nil, history)
  assert(displayed == [[]] && $spoken_messages.empty?, 'Initial history replayed old announcements')

  entries << entry_class.new(2, 'Bob', 'uno', 'joined')
  now += EltenGameRoom::LOBBY_ACTIVITY_POLL_INTERVAL
  app.send(:poll_lobby_activity, nil, history)
  Timeout.timeout(3) { received.pop }
  now += 100 # No burst of catch-up requests after a slow response.
  release << true
  assert(work.instance_variable_get(:@thread).join(3), 'Second history read did not finish')
  app.send(:poll_lobby_activity, nil, history)
  assert(displayed.last == ['event 2'] && $spoken_messages == ['event 2'], 'New history was not delivered once')
  100.times { app.send(:poll_lobby_activity, nil, history) }
  assert(calls == [:entries, :latest, :entries], 'Completion rescheduled overdue requests')

  now += EltenGameRoom::LOBBY_ACTIVITY_POLL_INTERVAL
  app.send(:poll_lobby_activity, nil, history)
  assert(work.instance_variable_get(:@thread).join(3), 'ID check did not finish')
  app.send(:poll_lobby_activity, nil, history)
  assert(calls.last == :latest && calls.count(:entries) == 2, 'Unchanged history was fetched in full')

  entries << entry_class.new(3, 'Bob', 'uno', 'joined')
  now += EltenGameRoom::LOBBY_ACTIVITY_POLL_INTERVAL
  app.send(:poll_lobby_activity, nil, history)
  Timeout.timeout(3) { received.pop }
  work.close
  release << true
  assert(work.instance_variable_get(:@thread).join(3), 'Closed read did not finish')
  app.send(:poll_lobby_activity, nil, history)
  assert(displayed.last == ['event 2'] && work.take.nil?, 'Closed menu accepted a late result')
ensure
  work.close
  release << true
  work.instance_variable_get(:@thread)&.join(3)
end
puts 'Lobby: immediate cached menu, finite background reads, baseline/dedup, completion pacing and late-close result: OK'
