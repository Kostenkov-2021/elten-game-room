require_relative "../support/private_table_creation"

announcements = []
original_announcement = EltenGameRoom.method(:announce_new_public_table)
EltenGameRoom.define_singleton_method(:announce_new_public_table) { |table| announcements << table }
begin
  [false, true].each do |private_table|
    game = GameRoomGames::Uno.new
    app = CreationFormApp.new(game)
    preset = GameRoomTablePresets.build(game, {game_options: game.normalize_options("thinking_time" => 25), private_table: private_table}, name: "UNO 25")
    app.define_singleton_method(:prepare_widget_program) { true }
    app.define_singleton_method(:game_room_settings) { |**_| {"table_presets" => [preset]} }
    Form.driver = ->(_) { raise "quick creation reopened options" }
    before = announcements.length
    app.send(:create_table_from_widget, 0)
    assert(app.lobby.creations.length == 1 && app.opened_tables.length == 1, "preset did not create exactly one table")
    assert(app.lobby.creations.first[:private_table] == private_table, "preset privacy lost")
    assert(JSON.parse(app.lobby.creations.first[:game_options]) == preset["options"], "preset options changed")
    assert(announcements.length - before == (private_table ? 0 : 1), "preset publication scope wrong")
    # A second explicit create requests the preset again, without a warning
    # or redirect to an earlier membership.
    before = announcements.length
    app.send(:create_table_from_widget, 0)
    assert(app.lobby.creations.length == 2 && app.opened_tables.length == 2, 'Repeated preset request did not create another table')
    assert(announcements.length - before == (private_table ? 0 : 1), 'Repeated preset publication scope wrong')
    assert(app.notices.empty?, 'Explicit creation reported an unrelated existing table')
  end
ensure
  EltenGameRoom.define_singleton_method(:announce_new_public_table, original_announcement)
end

# The actual options editor must restore privacy without moving focus from
# the instructions, and editing presets must not overwrite remembered rules.
game = GameRoomGames::Makao.new
app = CreationFormApp.new(game)
entry = GameRoomTablePresets.build(game, {game_options: game.normalize_options("profile" => "custom", "allow_playable_draw" => false), private_table: true}, name: "Moje Makao")
forms = 0
Form.driver = lambda do |form|
  forms += 1
  assert(forms == 1, "extra naming form after preset options")
  assert(form.index == 0 && privacy_field(form).checked, "preset editor lost initial focus/privacy")
  field = form.fields.find { |f| f.is_a?(CheckBox) && f.header == "Allow drawing with a playable card" }
  assert(field && !field.checked && !form.hidden_controls.include?(field), "custom drawing setting lost or hidden")
  form.accept_button.trigger(:press)
end
edited = app.send(:edit_table_preset, entry)
assert(edited == entry.merge("name" => game.name) && forms == 1, "preset edit silently changes options")
assert(app.remembered.empty? && app.lobby.creations.empty?, "preset editing has live/remembered side effects")
puts "Preset creation integration: common lobby, fresh public/private requests, editor/focus and no automatic game start OK"
