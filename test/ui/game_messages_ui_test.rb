require_relative "../support/ui"
require_relative "../../lib/game_surfaces"
require_relative "../../lib/game_screen"
require_relative "../../games/makao"

def assert(value, message)
  raise message unless value
end

game = GameRoomGames::Makao.new
state = game.send(:initial_state, %w[Alice Bob], game.default_options)
state.update(phase: :playing, current_player: "Alice", hands: { "Alice" => %w[5C 5D 5H], "Bob" => %w[6C] })
view = GameRoomGames::Replay.new(players: state[:players], state: state, current_player: "Alice")
surface = GameSurfaces.build(game.surface_spec(view, "Alice"))
surface.instance_variable_set(:@selected_ids, %w[5H 5C])
before = surface.state
$spoken_messages.clear
assert(surface.handle_command("announce_packet"), "P not handled")
assert($spoken_messages == ["5 of hearts, 5 of clubs"], "Packet order is wrong: #{$spoken_messages}")
assert(surface.state == before, "Reading packet changes selection")
surface.handle_command("clear_packet")
surface.handle_command("announce_packet")
assert($spoken_messages.last == "No packet prepared.", "Empty packet not announced")

# Surface controls can survive updates, unlike the temporary shortcut list.
field = surface.fields.first
FakeControl.class_eval do
  def get_tips
    ["Native tip", "Native tip"]
  end
end
screen = GameScreen.allocate
layout = GameRoomLayout::Screen.new(view_spec: GameRoomLayout::ViewSpec.new(surface: game.surface_spec(view, "Alice")), history_items: [], user_items: [])
shortcuts = game.game_shortcuts(view, "Alice")
GameRoomContextHelp.replace([field], ["Context action"])
inherited_tips = field.get_tips.uniq
5.times { screen.send(:bind_game_shortcuts, layout.form, [field], shortcuts) {} }
tips = field.get_tips
expected_tips = shortcuts.map do |shortcut|
  "#{GameRoomShortcutBindings.key_label(shortcut)}, #{shortcut.label}."
end + inherited_tips
# Enter/Shift+Enter belong to the card control, not the dynamic shortcut list.
assert(tips == expected_tips.uniq, "Help accumulates or drops control tips on retained fields")
screen.send(:bind_game_shortcuts, layout.form, [field], shortcuts.reject { |s| s.key == "p" }) {}
assert(field.game_room_game_help_tips.none? { |t| t.include?("prepared packet") }, "Obsolete shortcuts survive phase change")
assert(field.get_tips.include?("Press Shift+Enter to add or remove the current card from the prepared packet."), "Permanent packet help disappeared")
assert(field.get_tips.include?("Native tip") && field.get_tips.include?("Context action"), "Native or context help disappeared")
GameRoomContextHelp.replace(layout.form.fields, ["Game action"], source: :game)
GameRoomContextHelp.replace(layout.form.fields, ["Context action"])
layout.begin_bindings
assert(layout.form.fields.all? { |f| !f.get_tips.include?("Game action") && f.get_tips.include?("Context action") }, "Game help not cleared between games")
puts "Packet reading and shared dynamic F1 help passed"
