require_relative 'support/table_lifecycle_controls_2'

$game_room_test_user = 'Alice'
broker = NativeLiveSessionsBroker.new
app = LifecycleApp.new(broker)
table = app.lobby.create_table(name: 'Master selection', game: 'four_in_a_row', owner: 'Alice', game_options: '{}').table
%w[Bob Watcher].each { |user| GameRoomTransport.new(ProgramDouble.new(broker.endpoint(user))).join_room(table, user) }
app.lobby.set_observer(table, 'Watcher', true)
room = app.lobby.snapshot_for(table)
bot = GameRoomParticipants.bot_id(table['__id'], 1)
rows = RoomPresentation.user_rows(room.members + [bot], observers: room.observers, owner: 'Alice', players: %w[Alice Bob], active: true)
layout = GameRoomLayout::Screen.new(view_spec: GameRoomLayout::ViewSpec.new, user_items: rows, users_header: 'Users', phase: :active, own_table: true)
actions = [:manage_control, :edit_options]
called = []
GameRoomParticipantMenu.bind(layout, available: -> { actions }, room: -> { room }, control: -> { {active: true, players: %w[Alice Bob]} }) { |*args| called << args }
menu_for = ->(index) { layout.users.index = index; menu = LifecycleMenu.new; layout.users.context(menu, false); menu }
[0, 3, -1, 99].each do |index|
  assert(menu_for.call(index).items.none? { |item| item[1] == 'm' }, 'Self, bot or missing selection can receive ownership')
  assert(GameRoomContextHelp.field_tips(layout.users).none? { |tip| tip.include?('Ctrl+M') }, 'Help offers an impossible transfer')
end
[1, 2].each do |index|
  assert(menu_for.call(index).items.one? { |item| item[1] == 'm' }, 'Player/observer transfer missing')
  assert(GameRoomContextHelp.field_tips(layout.users).one? { |tip| tip.include?('Ctrl+M') }, 'Selected human has no transfer help')
end
command = menu_for.call(1).items.find { |item| item[1] == 'm' }.last
layout.users.index = 2
command.call
assert(called == [[:transfer_master, 'Bob']], 'Changing selection changed the captured recipient')
room.members.delete('Bob')
command.call
assert(called.length == 1, 'A departed recipient received ownership')
command = menu_for.call(2).items.find { |item| item[1] == 'm' }.last
actions.clear
command.call
assert(called.length == 1, 'Old owner retained permission through a stale menu')
layout.form.fields.each do |field|
  tips = GameRoomContextHelp.field_tips(field)
  assert(tips.none? { |tip| tip.include?('Ctrl+M') || tip.include?('Ctrl+X') }, 'Help kept lost rights')
end
actions << :edit_options
layout.form.fields.grep(EditBox).each do |field|
  assert(GameRoomContextHelp.field_tips(field).none? { |tip| tip.include?('Ctrl+X') }, 'Text field claims the cut shortcut')
end
global = LifecycleMenu.new
layout.form.context(global)
assert(global.items.none? { |item| item[1] == 'm' }, 'Ctrl+M remains global')
puts 'Selected master: focus, permissions, observer, invalid selection, stale menu and text editing: OK'
