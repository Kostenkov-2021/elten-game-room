require_relative "../support/table_lifecycle_controls_2"

$game_room_test_user = 'Alice'
broker = NativeLiveSessionsBroker.new
app = LifecycleApp.new(broker)
table = app.lobby.create_table(name: 'Selected participant', game: 'four_in_a_row', owner: 'Alice', game_options: '{}').table
%w[Bob Watcher].each { |user| GameRoomTransport.new(ProgramDouble.new(broker.endpoint(user))).join_room(table, user) }
app.lobby.set_observer(table, 'Watcher', true)
session = app.games.start_session(table: table, game: 'four_in_a_row', players: %w[Alice Bob], options: '{}')
room = app.lobby.snapshot_for(table)
players = %w[Alice Bob]
active = true
actions = [:manage_control]
rows = RoomPresentation.user_rows(room.members, observers: room.observers, owner: 'Alice', players: players, active: active)
layout = GameRoomLayout::Screen.new(view_spec: GameRoomLayout::ViewSpec.new, history_items: [], user_items: rows, users_header: 'Users', phase: :active, own_table: true)
called = []
GameRoomParticipantMenu.bind(layout, available: -> { actions }, game: GameRoomGames::FourInARow.new,
  room: -> { room }, control: -> { {active: active, players: players} }) { |*args| called << args }
menu = LifecycleMenu.new
layout.form.context(menu)
assert(menu.items.none? { |item| item[1] == 'R' }, 'Ctrl+Shift+R leaked outside Users')
layout.form.fields.reject { |f| f.equal?(layout.users) }.each do |field|
  assert(GameRoomContextHelp.field_tips(field).none? { |tip| tip.include?('Ctrl+Shift+R') }, 'Replacement help leaked to another field')
end
assert(GameRoomContextHelp.field_tips(layout.users).one? { |tip| tip.include?('Ctrl+Shift+R') }, 'Users help is absent/duplicated')
layout.users.index = 1
menu = LifecycleMenu.new
layout.users.context(menu, false)
command = menu.items.find { |item| item[1] == 'R' }
assert(command, 'Selected player has no shortcut')
command.last.call
assert(called == [[:replace_player, 'Bob']], 'Shortcut lost the selected participant')
layout.users.index = 2
menu = LifecycleMenu.new
layout.users.context(menu, false)
assert(menu.items.none? { |item| item[1] == 'R' }, 'Observer can be the source')
actions.clear
command.last.call
assert(called.size == 1, 'Stale menu retained master rights')
actions << :manage_control
players.replace(%w[Alice Watcher])
command.last.call
assert(called.size == 1, 'Stale selected player was replaced again')

dialogs = []
app.define_singleton_method(:choose_table_participant) do |candidates, header|
  dialogs << [candidates, header]
  'Watcher'
end
assert(!app.send(:change_table_control, table, :replace_player), 'A missing selection opened another picker')
assert(dialogs.empty?, 'Unexpected first dialog')
assert(app.send(:change_table_control, table, :replace_player, 'Bob'), 'Selected-row replacement failed')
assert(dialogs == [[['Watcher', :new_bot], 'Choose the replacement']], 'Replacement dialog contains playing participants or a source picker')
assert(app.games.session_for_table(table)['__players'] == %w[Alice Watcher], 'Replacement did not inherit the place')

scrabble = GameRoomGames::Scrabble.new
players = %w[Alice Bob]
assert(GameRoomParticipantMenu.replacement_candidates(room: room, players: players, participant: 'Bob', game: scrabble) == ['Watcher'], 'No-bot game offered a bot')
bot = GameRoomParticipants.bot_id(table['__id'], 1)
assert(GameRoomParticipantMenu.replacement_candidates(room: room, players: ['Alice',bot], participant: bot, game: GameRoomGames::FourInARow.new) == %w[Bob Watcher], 'Replacing a bot offers another bot')

before_cancel = broker.cores.values.first.last_seq
app.define_singleton_method(:choose_table_participant) { |*_args| nil }
assert(!app.send(:change_table_control, table, :replace_player, 'Watcher'), 'Cancelling replacement changed the table')
assert(broker.cores.values.first.last_seq == before_cancel, 'Cancelled replacement wrote a server record')

empty_broker = NativeLiveSessionsBroker.new
empty_app = LifecycleApp.new(empty_broker)
empty_table = empty_app.lobby.create_table(name: 'Nobody to replace', game: 'scrabble', owner: 'Alice', game_options: '{}').table
GameRoomTransport.new(ProgramDouble.new(empty_broker.endpoint('Bob'))).join_room(empty_table, 'Bob')
empty_app.games.start_session(table: empty_table, game: 'scrabble', players: %w[Alice Bob], options: '{}')
empty_app.define_singleton_method(:choose_table_participant) { |*_args| raise 'Empty replacement picker opened' }
before_empty = empty_broker.cores.values.first.last_seq
assert(!empty_app.send(:change_table_control, empty_table, :replace_player, 'Bob'), 'No-bot table invented a replacement')
assert(empty_app.notices.last == 'There is nobody available to replace this player.', 'Missing empty replacement explanation')
assert(empty_broker.cores.values.first.last_seq == before_empty, 'Empty replacement changed server state')

# Someone leaves or takes another place while the picker is still open.
app.define_singleton_method(:choose_table_participant) do |_candidates, _header|
  app.transport.replace_game_player(table, session_id: session['__id'], player: 'Alice', replacement: 'Bob')
  'Bob'
end
before = app.games.session_for_table(table)['__players']
begin
  app.send(:change_table_control, table, :replace_player, 'Watcher')
  raise 'Stale choice silently exchanged occupied places'
rescue GameRoomNetworkErrors::GamePaused
end
assert(app.games.session_for_table(table)['__players'] == ['Bob',before.last], 'Stale choice overwrote the other control change')
puts 'Selected-row replacement: local shortcut/help, one picker, valid people only, no bots where unsupported, stale permission/selection: OK'
