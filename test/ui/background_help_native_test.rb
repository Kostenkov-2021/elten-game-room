# Load the same real ELTEN controls/input/speech adapter used for the tutorial.
# It also runs the existing standalone tutorial regression before this one.
require_relative "../support/background_help_native"

driver = BackgroundHelpNativeDriver.new
$native_tutorial_driver = driver
SpeechOutput.reset
EltenAPI::KeyboardState.reset
game = ListBox.new(['First card', 'Second card'], header: 'Hand', quiet: true)
updates = 0
game.singleton_class.prepend(Module.new do
  define_method(:update) { updates += 1; super() }
end)
root = GameRoomUI::Form.new([game], quiet: true)
driver.root = root
root.game_room_background_help_enabled = true
root.show_game_room_help
help = root.game_room_background_help_form
assert(help && help.fields.first.is_a?(GameRoomUI::HelpText), 'F1 still used a modal wait')
help.fields.first.set_text("First line\nSecond line\nThird line")
ticks = 0
root.add_timer(FormTimer.new(0, repeat: true) do
  ticks += 1
  root.resume if ticks % 3 == 0
end)
driver.keys = [[], [0x28], []]
root.wait
position = help.fields.first.index
assert(position > 0 && updates.zero? && ticks == 3, 'Native help arrow reached the hand or stopped timers')
reads = SpeechOutput.calls.length
driver.keys = [[], [], []]
root.wait
assert(root.game_room_background_help_form.equal?(help) && help.fields.first.index == position,
  'Native refresh recreated or moved the help document')
assert(SpeechOutput.calls.length == reads && updates.zero? && ticks == 6,
  'Re-entering the native wait reread help or updated the game field')
driver.keys = [[0x0D], [], []]
root.wait
assert(!root.game_room_background_help? && game.index == 0, 'Native Enter failed to close help cleanly')
assert(updates == 2, 'Closing help passed its Enter through to the game field')
assert(!help.game_room_hotkeys_active?, 'Closed overlay retained the hotkey override')
puts 'PASS native background help: real input/control loop, arrows, timers, retained caret, quiet maintenance and isolated closing Enter'
