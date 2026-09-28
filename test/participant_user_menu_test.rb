require_relative 'support/table_lifecycle_controls_2'

rows = RoomPresentation.user_rows(%w[Alice Bob Watcher], observers: ['Watcher'], owner: 'Alice', players: %w[Alice Bob], active: true)
bot = GameRoomParticipants.bot_id(12, 1, name_token: 'pl01')
rows.concat(RoomPresentation.user_rows([bot], observers: [], owner: 'Alice', players: [bot], active: true))
layout = GameRoomLayout::Screen.new(view_spec: GameRoomLayout::ViewSpec.new, history_items: [], user_items: rows,
  users_header: 'Users', phase: :active, own_table: true)
calls = []
layout.chat.set_text('Unsent draft')
layout.form.index = layout.form.fields.index(layout.users)
20.times do
  layout.begin_bindings
  GameRoomParticipantMenu.bind(layout, available: -> { [] }, user_menu: ->(user) { calls << user }) { raise 'Menu dispatched a game action' }
end
%w[Alice Bob Watcher].each_with_index do |user, index|
  layout.users.index = index
  layout.users.trigger(:select)
  assert(calls.last == user, 'Native menu did not receive the selected login')
end
assert(calls == %w[Alice Bob Watcher], 'Rebinding multiplied native menu handlers')
layout.users.index = 3
layout.users.trigger(:select)
layout.users.index = -1
layout.users.trigger(:select)
layout.users.index = 200
layout.users.trigger(:select)
assert(calls.size == 3, 'A bot or invalid row was treated as an account')
assert(layout.chat.text == 'Unsent draft', 'User menu lost the draft')
assert(layout.focus_location == [:users, 0], 'User menu changed the focused field')
layout.update_users(rows.reverse)
layout.users.index = 2
layout.users.trigger(:select)
assert(calls.last == 'Bob', 'Reordered row resolved a stale login')
layout.chat.trigger(:select)
layout.history.trigger(:select)
assert(calls.size == 4, 'User menu leaked to another field')
layout.update_users([])
layout.users.index = 0
layout.users.trigger(:select)
assert(calls.size == 4, 'Empty list opened an account')
puts 'Participant user menu: real identity, all human roles, no bots, no duplicate bindings, scoped activation and preserved draft: OK'
