require_relative "../support/session_runner"
require_relative "../../games/farkle"
require_relative "../../lib/table_activity_repository"

h = NativeRoomHarness.new(game: GameRoomGames::Farkle.new, users: %w[Alice Bob Carol],
  options: GameRoomGames::Farkle.new.default_options.merge('bot_delay' => 0))
h.start
rs = h.users.to_h { |u| [u, runner_for(h, u)] }
h.users.each { |u| step(h, rs[u], u) }
sid = h.session['__id']
before = h.events('Bob').map { |e| e['__id'] }
h.as('Alice') do
  lobby = LobbyRepository.new(ProgramDouble.new(h.broker.endpoint('Alice')), transport: h.transports['Alice'], server_tables: Object.new)
  assert(lobby.leave_table(h.table, 'Alice') == :left, 'Owner leave closed the game')
end
step(h, rs['Bob'], 'Bob', count: 4)
current = h.repositories['Bob'].session_for_table(h.transports['Bob'].room_snapshot(h.table)[:table])
assert(current['__id'] == sid && current['__table_owner'] == 'Bob', 'Owner succession replaced match')
bot = current['__players'].first
assert(GameRoomParticipants.bot?(bot), 'Confirmed departure did not physically replace the seat')
room_data = h.transports['Bob'].room_snapshot(h.table)
# The runner publishes the current status; active seats include the replacement.
assert(LobbyRepository::TableSnapshot.new(**room_data).participant_count == 3, 'Departed bot-controlled seat vanished from the active count')
assert(h.events('Bob').map { |e| e['__id'] }.first(before.size) == before, 'History changed after succession')
assert(h.events('Bob').any? { |e| e['actor'] == bot }, 'Replacement never played the departed seat')
step(h, rs['Carol'], 'Carol', count: 2)
assert(h.events('Bob') == h.events('Carol'), 'Third reader disagrees after succession')
activity = TableActivityRepository.new(transport: h.transports['Bob'], server_tables: Object.new)
rows = activity.entries_for(h.transports['Bob'].room_snapshot(h.table)[:table])
assert(rows.count { |e| e.kind == 'owner_changed' } == 1, 'Owner announcement missing or duplicated')
assert(rows.count { |e| e.kind == 'player_replaced' && e.subject == 'Alice' && e.replacement == bot } == 1, 'Named replacement announcement missing or duplicated')
# A return is not an implicit takeover; only the master restores that seat.
h.join('Alice')
step(h, rs['Bob'], 'Bob', count: 2)
current = h.repositories['Bob'].session_for_table(h.table)
assert(current['__players'].first == bot, 'Rejoining stole control from bot')
h.as('Bob') { h.transports['Bob'].replace_game_player(h.table, session_id: sid, player: bot, replacement: 'Alice') }
current = h.repositories['Bob'].session_for_table(h.table)
assert(current['__players'].first == 'Alice', 'Explicit human restoration failed')
rs.each_value(&:close)
puts 'Three-seat controller succession, replacement, history and restoration: OK'
