require_relative "../support/widget_inline_presets"

# Real Settings -> game selector -> real options -> immediate local write.
# The parent Cancel must discard only the unrelated staged settings.
app = InlinePresetApp.new
forms = []
Form.driver = lambda do |form|
  forms << form
  if forms.length == 1
    list = inline_presets(form)
    assert(list.options.first == "Ctrl+1: Not assigned. Press Enter to assign.", "empty slot has no assignment hint")
    assert(list.options[9].start_with?("Ctrl+0:") && list.options.last.start_with?("Shift+0:"), "zero slot order")
    form.fields.find { |field| field.is_a?(CheckBox) && field.header == 'Announce when a table is created' }.checked = false
    list.index = 9
    form.accept_button.trigger(:press)
    assert(app.writes.length == 1, "assignment not saved immediately")
    saved = app.stored.fetch("table_presets")[9]
    assert(saved["game"] == "makao" && saved["private_table"], "saved wrong game/privacy")
    assert(list.index == 9 && form.fields[form.index].equal?(list), "editing lost selected slot/focus")
    assert(list.options[9] == "Ctrl+0: Makao. Press Enter to edit.", "assigned hint not updated")
    form.cancel_button.trigger(:press)
  else
    assert(forms.length == 2 && form.fields.first.is_a?(Static), "extra name or preset-list dialog opened")
    privacy_field(form).checked = true
    form.accept_button.trigger(:press)
  end
end
app.send(:show_settings)
assert(app.choices == 1 && forms.length == 2, "unexpected editor steps")
assert(app.stored["sentinel"] == "keep" && app.stored["lobby_games"] == InlinePresetApp::GAME_REGISTRY.ids, "Cancel saved unrelated fields")
assert(app.stored["announce_table_created"], "Cancel saved another category's pending edits")
assert(app.stored["table_presets"][9]["private_table"], "parent Cancel undid the assignment")
assert(app.send(:game_room_settings)["table_presets"][9]["private_table"], "settings cache lost immediate assignment")
assert(app.lobby.creations.empty? && app.opened_tables.empty?, "editing opened a live table")
assert(app.network_calls.empty?, "local preset editing or settings entry started a blocking network task")

# Cancel in either editor step leaves the previous slot intact.
saved = JSON.parse(JSON.generate(app.stored))
[true, false].each do |cancel_game|
  app.cancel_game = cancel_game
  Form.driver = lambda do |form|
    if form.fields.first.is_a?(Static)
      form.cancel_button.trigger(:press)
    else
      list = inline_presets(form); list.index = 9
      form.accept_button.trigger(:press)
      form.cancel_button.trigger(:press)
    end
  end
  app.send(:show_settings)
  assert(app.stored == saved && app.writes.length == 1, "cancelled editor changed an assignment")
end

# Parent Save must neither restore an old slot nor overwrite a more recent
# stored slot with the stale copy held when Settings was opened.
Form.driver = lambda do |form|
  list = inline_presets(form)
  entry = GameRoomTablePresets.build(GameRoomGames::Uno.new,
    {game_options: GameRoomGames::Uno.new.default_options, private_table: false})
  app.send(:save_table_preset, 0, entry)
  form.index = form.fields.index(form.accept_button)
  form.accept_button.trigger(:press)
end
app.send(:show_settings)
assert(app.stored["table_presets"][0]["game"] == "uno" && app.stored["table_presets"][9]["game"] == "makao", "parent Save restored stale assignments")
assert(app.send(:game_room_settings)["table_presets"][0]["game"] == "uno", "parent Save cache lost assignment")

puts "Inline widget presets: last field, two-step editing, immediate save, parent/child Cancel, parent Save, privacy, cache and no table creation OK"
