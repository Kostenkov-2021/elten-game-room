require_relative "../support/widget_presets"

presets = GameRoomTablePresets
registry = EltenGameRoom::GAME_REGISTRY
assert(presets.slots(nil) == Array.new(30), "empty presets")
registry.ids.each do |id|
  game = registry.build(id)
  entry = presets.build(game, {game_options: game.default_options, private_table: false})
  assert(presets.valid?(entry, game), "default preset invalid: #{id}")
end
game = registry.build("makao")
entry = presets.build(game, {game_options: game.normalize_options("profile" => "custom", "allow_playable_draw" => false), private_table: true}, name: "Makao prywatne")
assert(presets.valid?(entry, game), "custom preset invalid")
assert(!presets.valid?(entry.merge("options" => entry["options"].merge("profile" => "removed")), game), "obsolete choice silently normalized")
assert(!presets.valid?(entry.merge("options" => entry["options"].merge("deleted_option" => true)), game), "removed option silently discarded")
assert(!presets.valid?(entry, nil), "removed game silently substituted")
assert(!presets.valid?(entry.merge("private_table" => "yes"), game), "malformed privacy accepted")
copy = presets.slots([entry]); copy[0]["options"]["profile"] = "simple"
assert(entry["options"]["profile"] == "custom", "editing mutates saved preset before Save")
assert(presets.label(9, entry).start_with?("Ctrl+0:"), "last slot is not Ctrl+0")

# Use native first-press semantics: modifier combinations and repeats must not
# create tables or become ListBox character searches.
events = []
active = true
widget = GameRoomWidget::TableList.new(loader: -> { raise "creation refreshed widget" }, opener: ->(*) {}, labeler: ->(*) {}, id_for: ->(*) {},
  creator: ->(slot) { events << slot; widget.send(:create_table, slot) },
  worker: WidgetManualWorker.new, active: -> { active }, clock: -> { 0 })
pressed = nil
widget.define_singleton_method(:main_shortcut_pressed?) do |key, first:|
  assert(first, "shortcut accepts held-key repeats")
  pressed == key
end
(%w[n] + presets::KEYS).each { |key| pressed = key; widget.update }
assert(events == [nil] + (0..9).to_a, "shortcut mapping/reentrancy: #{events.inspect}")
active = false; pressed = "1"; widget.update
assert(events.length == 11, "off-widget shortcut fired")
assert(widget.get_tips.count { |tip| tip.start_with?("Ctrl+") } == 11, "widget shortcut help missing")
global = FakeMenu.new; widget.context(global)
assert(global.options.empty?, "widget actions leaked to global context")

# Exercise the host's real modifier/first-press helper as well. Only its
# physical keyboard state is substituted; no running ELTEN is touched.
widget.singleton_class.send(:remove_method, :main_shortcut_pressed?)
widget.extend(EltenAPI::UI)
first = true
modifiers = [:control]
widget.define_singleton_method(:keyboard_code) { |key| [key.to_s.upcase.ord, false] }
widget.define_singleton_method(:raw_key_first_pressed?) { |key| first && key == pressed.to_s.upcase.ord }
widget.define_singleton_method(:raw_key_pressed?) { |key| key == pressed.to_s.upcase.ord }
widget.define_singleton_method(:keyboard_modifier_held_when_pressed?) { |_, modifier| modifiers.include?(modifier) }
widget.define_singleton_method(:key_pressed?) { |_| false }
widget.instance_variable_set(:@refresh_at, Float::INFINITY)
active = true; pressed = "1"
count = events.length
widget.update
assert(events.length == count + 1 && events.last == 0, "real host shortcut helper rejected Ctrl+1")
first = false
100.times { widget.update }
assert(events.length == count + 1, "held shortcut created more than one table")
first = true
[[], [:control, :shift], [:control, :option], [:shift, :option]].each do |held|
  modifiers = held
  widget.update
end
assert(events.length == count + 1, "extra modifiers or bare digits invoked shortcut")

presets::BINDINGS.each_with_index do |(key, modifier), slot|
  pressed, modifiers = key, [modifier]
  widget.update
  assert(events.last == slot, "native modifier mapping failed for #{presets.shortcut(slot)}")
end
assert(presets.slots(Array.new(10) { entry }).last(20) == Array.new(20), 'new slots are not empty on migration')

# Use the app's ordinary table-creation entry point, never a second network
# implementation. Empty slots must not connect, create or open dialogs.
app = EltenGameRoom.allocate
state = {"table_presets" => presets.slots([entry]), "unrelated" => "keep"}
calls = []
app.define_singleton_method(:game_room_settings) { |**_| state }
app.define_singleton_method(:prepare_widget_program) { calls << :prepare }
app.define_singleton_method(:show_create_table) { calls << :choose_game }
app.define_singleton_method(:create_configured_table) { |g, config| calls << [g.id, config] }
app.define_singleton_method(:alert) { |text| calls << text }
app.define_singleton_method(:update_json) { |_, default:, &block| state = block.call(state) }
app.send(:create_table_from_widget)
assert(calls == [:prepare, :choose_game], "Ctrl+N misses normal game chooser")
calls.clear
app.send(:create_table_from_widget, 0)
assert(calls == [:prepare, ["makao", {game_options: entry["options"], private_table: true}]], "preset does not use saved configuration")
calls.clear
app.send(:create_table_from_widget, 9)
assert(calls.length == 1 && calls.first.include?("No table preset"), "empty slot connects or opens editor")
state["table_presets"][0]["options"]["profile"] = "removed"
app.define_singleton_method(:edit_table_preset) { |_| calls << :repair; nil }
calls.clear; app.send(:create_table_from_widget, 0)
assert(calls.length == 2 && calls.last == :repair, "invalid preset created table without approval")
fixed = presets.build(game, {game_options: game.default_options, private_table: false})
app.define_singleton_method(:edit_table_preset) { |_| fixed }
calls.clear; app.send(:create_table_from_widget, 0)
assert(calls[-1] == ["makao", {game_options: fixed["options"], private_table: false}], "repaired preset not used")
assert(state["unrelated"] == "keep" && state["table_presets"][0] == fixed, "repair persistence overwrites settings")

# Inline list edits persist independently of the main Settings transaction.
old_wait = Form.instance_method(:wait)
driver = nil
Form.send(:define_method, :wait) { driver.call(self) }
begin
  original = GameRoomPreferences.defaults(registry.ids).merge("table_presets" => presets.slots([entry]))
  stored = presets.slots([entry])
  writes, alerts, edits = [], [], 0
  fail_write = false
  cancel_edit = false
  editor = lambda do |old_entry|
    edits += 1
    if cancel_edit
      old_entry["name"] = "unsaved mutation"
      nil
    else
      fixed
    end
  end
  writer = lambda do |slot, value|
    raise IOError, "synthetic write error" if fail_write
    stored[slot] = value
    writes << [slot, value]
  end
  driver = lambda do |form|
    form.fields.first.index = form.fields.first.options.index('Widget') || raise('Missing Widget category')
    form.fields.first.trigger(:move)
    list = form.fields.find { |field| field.is_a?(GameRoomScreens::TablePresetList) }
    assert(list && !form.hidden_controls.include?(list), "missing inline Widget list")
    assert(list.options.length == 30 && list.options.first.include?("Press Enter to edit.") &&
      list.options.last.include?("Press Enter to assign."), "slot hints are wrong")
    list.define_singleton_method(:alert) { |text| alerts << text }
    form.index = form.fields.index(list)
    list.index = 9
    form.accept_button.trigger(:press)
    assert(writes.length == 1 && stored[9] == fixed && list.index == 9, "immediate save/cursor lost")
    list.index = 0
    cancel_edit = true
    form.accept_button.trigger(:press)
    assert(writes.length == 1 && stored[0] == entry && !list.options.first.include?("unsaved"), "cancelled edit mutates the slot")
    cancel_edit = false
    fail_write = true
    form.accept_button.trigger(:press)
    assert(writes.length == 1 && stored[0] == entry && !alerts.empty?, "failed save accepted silently")
    assert(list.options.first.include?("Makao prywatne"), "failed save shows the unsaved choice")
    fail_write = false
    global = FakeMenu.new; list.context(global, true)
    assert(global.options.empty?, "preset operations leaked to other controls")
    local = FakeMenu.new; list.context(local, false)
    local.options.find { |item| item.first == "Clear assignment" }.last.call
    assert(stored[0].nil? && stored[9] == fixed && writes.length == 2, "clear touches other slots")
    assert(list.options.first.include?("Press Enter to assign."), "cleared hint stale")
    form.cancel_button.trigger(:press)
  end
  result = GameRoomScreens::Settings.new(original, games: [],
    preset_editor: editor, preset_writer: writer).wait
  assert(result.nil? && stored[9] == fixed && stored[0].nil?, "main Cancel reversed committed edits")
  assert(original["table_presets"][0] == entry, "opening-time settings mutated")
ensure
  Form.send(:define_method, :wait, old_wait)
end
puts "Widget presets: thirty slots, validation, privacy, native scope, immediate local save/clear and independent cancellation OK"
