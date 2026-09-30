require_relative "../support/host_source"
require_relative "../support/widget_inline_presets"
load EltenTestHost.file("src/ui/input.rb")
module EltenAPI::KeyboardScheme
  def self.main_modifier; :control; end
  def self.key_code(key); key.is_a?(Integer) ? key : nil; end
end

app = InlinePresetApp.new
Form.driver = lambda do |form|
  list = inline_presets(form)
  form.extend(EltenAPI::UI)
  pressed, modifiers, first = '1', [:control], true
  form.define_singleton_method(:keyboard_code) { |key| [key.to_s.upcase.ord, false] }
  form.define_singleton_method(:raw_key_first_pressed?) { |key| first && key == pressed.to_s.upcase.ord }
  form.define_singleton_method(:keyboard_modifier_held_when_pressed?) { |_, modifier| modifiers.include?(modifier) }
  GameRoomTablePresets::BINDINGS.each_with_index do |(key, modifier), slot|
    pressed, modifiers = key, [modifier]
    form.index = 0 # Not necessary to tab to the shortcut list first.
    form.update
    assert(form.fields[form.index].equal?(list) && list.index == slot, 'shortcut did not select its row from Widget category')
    assert(app.writes.empty? && app.choices == 0, 'selecting a shortcut edited or created a table')
  end
  first = false
  list.index = 4
  form.update
  assert(list.index == 4, 'held shortcut repeated')
  first = true
  [[], [:control, :shift], [:control, :option], [:shift, :option]].each do |held|
    modifiers = held
    form.update
    assert(list.index == 4, 'extra modifiers or plain number selected a macro')
  end
  # Neither another category nor its editable fields are captured.
  form.fields.first.index = 0
  form.fields.first.trigger(:move)
  modifiers = [:control]
  form.index = 1
  form.update
  assert(form.index == 1 && list.index == 4, 'shortcut escaped the Widget settings category')
  form.cancel_button.trigger(:press)
end
app.send(:show_settings)
assert(app.writes.empty? && app.lobby.creations.empty?, 'navigation had side effects')
entry = GameRoomTablePresets.build(GameRoomGames::Makao.new,
  {game_options: GameRoomGames::Makao.new.default_options, private_table: true})
[0, 9, 10, 19, 20, 29].each { |slot| app.send(:save_table_preset, slot, entry) }
assert(app.stored['table_presets'].length == 30 && app.stored['table_presets'][29] == entry, 'new macros not persisted')
[-1, 30, '1'].each do |slot|
  begin
    app.send(:save_table_preset, slot, entry)
  rescue ArgumentError
    next
  end
  raise 'invalid macro index accepted'
end
puts 'PASS native 30 settings shortcuts: exact modifiers, focus, first press, category scope, no edits/creation and independent persistence'
