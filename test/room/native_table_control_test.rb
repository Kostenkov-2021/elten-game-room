require_relative "../support/native_live_sessions"
broker = NativeLiveSessionsBroker.new
users = %w[Alice Bob Carol]
transports = users.to_h { |u| [u, GameRoomTransport.new(ProgramDouble.new(broker.endpoint(u)))] }
lobbies = users.to_h { |u| [u, LobbyRepository.new(ProgramDouble.new(broker.endpoint(u)), transport: transports[u], server_tables: Object.new)] }
games = users.to_h { |u| [u, GameRepository.new(ProgramDouble.new(broker.endpoint(u)), transport: transports[u], server_tables: Object.new)] }
transports.each_value(&:start)
$game_room_test_user = "Alice"
table = lobbies['Alice'].create_table(name: 'Test', game: 'four_in_a_row', owner: 'Alice').table
users.drop(1).each do |u|
  $game_room_test_user = u
  row = lobbies[u].open_tables.first
  lobbies[u].join_table(row, u)
end
$game_room_test_user = 'Alice'
session = games['Alice'].start_session(table: table, game: 'four_in_a_row', players: users)
command = [{action: 'drop', value: '1'}]
games['Alice'].append_events(session: session, sequence: 0, events: command, actor: 'Alice')
transports['Alice'].transfer_room_owner(table, 'Bob')
$game_room_test_user = 'Bob'
room = lobbies['Bob'].snapshot_for(table)
assert(room.table['owner'] == 'Bob', 'Native owner not projected')
current = games['Bob'].session_for_table(room.table)
assert(current && current['__control_ready'], 'New owner could not continue the same game')
transports['Bob'].set_seat_controller(table, session_id: current['__id'], seat: 'Alice', bot: true)
current = games['Bob'].session_for_table(room.table)
bot = current['__players'].first
games['Bob'].append_events(session: current, sequence: 1, events: command, actor: bot)
rows = games['Bob'].snapshot_for(current).events
assert(rows.size == 2 && games['Bob'].actor_of(rows.last, current) == bot, 'Replacement retained the human identity')
$game_room_test_user = 'Alice'
begin
  games['Alice'].append_events(session: session, sequence: 2, events: command, actor: 'Alice')
  raise 'Old controller was allowed to submit'
rescue GameRoomNetworkErrors::GamePaused, ArgumentError
end
# A fresh reader has no in-memory knowledge of who previously owned the room.
$game_room_test_user = 'Carol'
fresh = GameRoomTransport.new(ProgramDouble.new(broker.endpoint('Carol', fresh: true)))
fresh.start
fresh_table = fresh.discover_rooms.first
fresh.join_room(fresh_table, 'Carol')
repo = GameRepository.new(ProgramDouble.new(nil), transport: fresh, server_tables: Object.new)
current = repo.session_for_table(fresh.room_snapshot(table)[:table])
assert(repo.snapshot_for(current).events.map { |e| repo.actor_of(e, current) } == ['Alice', bot], 'Late replay changed historical authors')
$game_room_test_user = 'Bob'
transports['Bob'].replace_game_player(table, session_id: current['__id'], player: bot, replacement: 'Alice')
current = games['Bob'].session_for_table(lobbies['Bob'].snapshot_for(table).table)
assert(current['__players'] == users, 'Human was not restored')
again = games['Bob'].start_session(table: room.table, game: 'four_in_a_row', players: users, expected_previous_session_id: current['__id'])
assert(again['__controllers'].empty?, 'Rematch retained replacement')
begin
  transports['Bob'].set_seat_controller(table, session_id: current['__id'], seat: 'Alice', bot: true)
  raise 'Stale previous-game menu changed a controller'
rescue GameRoomNetworkErrors::GamePaused
end
assert(games['Bob'].session_for_table(table)['__controllers'].empty?, 'Stale command changed the rematch')
puts 'Native table control: OK'
