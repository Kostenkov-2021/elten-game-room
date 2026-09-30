require_relative "../support/native_room_harness"

[[900, 100], [100, 900]].each do |ids|
  h = NativeRoomHarness.new(users: %w[Alice Bob Carol])
  transport = h.transports.fetch('Alice')
  store = transport.instance_variable_get(:@live_store)
  identifiers = ids.dup
  store.define_singleton_method(:unused_game_identifier) { |_table_id| identifiers.shift || raise('Unexpected start') }
  lobby = LobbyRepository.new(nil, transport: transport)
  repo = h.repositories.fetch('Alice')
  h.as('Alice') do
    lobby.set_observer(h.table, 'Carol', true)
    first = repo.start_session(table: h.table, game: 'test', players: %w[Alice Bob])
    transport.abort_game(first)
    lobby.set_observer(h.table, 'Bob', true)
    lobby.set_observer(h.table, 'Carol', false)
    second = repo.start_session(table: h.table, game: 'test', players: %w[Alice Carol], expected_previous_session_id: first['__id'])
    snapshot = lobby.snapshot_for(h.table)
    raise 'The actual latest game changed' unless repo.session_for_table(h.table)['__id'] == second['__id']
    raise 'A former player took priority over the current player' unless lobby.successor_for(snapshot, 'Alice') == 'Carol'
    raise 'Departure did not complete' unless lobby.leave_table(h.table, 'Alice') == :left
  end
  h.as('Carol') do
    current = h.transports.fetch('Carol').room_snapshot(h.table, force: true)
    raise 'The current player did not become master' unless current[:table]['owner'] == 'Carol'
  end
end

h = NativeRoomHarness.new(users: %w[Alice Bob])
h.as('Alice') do
  lobby = LobbyRepository.new(nil, transport: h.transports.fetch('Alice'))
  lobby.set_observer(h.table, 'Bob', true)
  raise 'A present observer cannot inherit an otherwise empty room' unless lobby.successor_for(lobby.snapshot_for(h.table), 'Alice') == 'Bob'
end
puts 'Successor: actual start order, current player priority, native transfer and observer fallback passed'
