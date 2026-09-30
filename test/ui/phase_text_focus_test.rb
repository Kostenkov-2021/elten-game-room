require_relative "../support/ui"
require_relative "../../lib/game_surfaces"
require_relative "../../lib/game_layout"

def assert(condition, message)
  raise message unless condition
end

spec = GameRoomLayout::ViewSpec.new(surface: GameSurfaces::GridSpec.new(
  width: 1, height: 1, header: 'Board', cells: [['empty']], row_origin: :bottom))
[:chat, :history, :users].product([true, false]).each do |field_name, owner|
  layout = GameRoomLayout::Screen.new(view_spec: spec, history_items: ['message one', 'message two'],
    user_items: ['Alice', 'Bob'], phase: :waiting, own_table: owner)
  original = [layout.form, layout.chat, layout.history, layout.users]
  layout.chat.text = 'An unfinished message: ąż'
  layout.chat.restore_selection(index: 7, check: 3)
  layout.history.entry_index = 0
  layout.form.index = layout.form.fields.index(layout.public_send(field_name))
  [[:active, false], [:finished, false], [:active, true], [:finished, false], [:waiting, false]].each do |phase, new_game|
    layout.update(view_spec: spec, history_items: ['message one', 'message two', 'new event'],
      user_items: ['Alice', 'Bob'], users_header: 'Users', phase: phase, new_game: new_game,
      reset_surface: new_game, own_table: owner)
    assert(layout.focus_location == [field_name, 0], "#{owner}/#{phase}: #{field_name} focus stolen")
    assert([layout.form, layout.chat, layout.history, layout.users] == original, 'shared fields were replaced')
    assert([layout.chat.text, layout.chat.index, layout.chat.check] == ['An unfinished message: ąż', 7, 3], 'chat text/caret/selection lost')
    assert(layout.history.entry_index.zero?, 'reading position in history lost')
  end
end

# Even a reader at the last event must not jump to the new final result.
layout = GameRoomLayout::Screen.new(view_spec: spec, history_items: ['old'], phase: :active)
layout.form.index = layout.form.fields.index(layout.history)
layout.update(view_spec: spec, history_items: ['old', 'game ended'], user_items: [], users_header: '', phase: :finished)
assert(layout.focus_location == [:history, 0] && layout.history.entry_index.zero?, 'end of game moved the focused history caret')

# The game/status controls retain their normal transition behaviour.
layout = GameRoomLayout::Screen.new(view_spec: spec, phase: :waiting, own_table: true)
assert(layout.focus_location == [:status, 0], 'initial room did not focus Start')
layout.update(view_spec: spec, history_items: [], user_items: [], users_header: '', phase: :active)
assert(layout.focus_location == [:game, 0], 'starting from Start did not focus the board')
layout.update(view_spec: spec, history_items: [], user_items: [], users_header: '', phase: :finished, own_table: true)
assert(layout.focus_location == [:status, 0], 'finishing on the board lost the restart control')
puts 'PASS persistent chat/history/users through start, finish and rematch; normal board transitions preserved'
