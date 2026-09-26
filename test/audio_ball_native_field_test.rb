# Real host Form/Button/EditBox/help dispatch, with OS/speech peripherals fake.
require_relative 'support/background_help_native'
module GameSurfaces
  module ActionEmitter; end
end
require_relative '../lib/game_surfaces/audio_ball_surface'

class AudioBallFieldNativeDriver
  def initialize; @time = 0.0; end
  def tick(_form); snapshot([], []); end
  def state(keys)
    result = "\0" * 256
    keys.each { |key| result.setbyte(key, 0x80) }
    result
  end
  def snapshot(events, held)
    @time += 0.016
    EltenAPI::KeyboardState.update(raw_state: state(held), events: events, now: @time,
      pressed_implies_held: false, synthesize_repeats: false)
    $input_frame_serial = $input_frame_serial.to_i + 1
    $keyboard_state_frame_serial = $input_frame_serial
    $keyboard_state_frame_thread = Thread.current
    $activecontrols = []
  end
  def frame(form, events = [], held: [])
    snapshot(events, held)
    form.update
  end
  def tap(code); [[code, true, state([code])], [code, false]]; end
end

driver = AudioBallFieldNativeDriver.new
$native_tutorial_driver = driver
EltenAPI::KeyboardState.reset
spec = GameSurfaces::AudioBallSpec.new(game_id: 'audio_ball', header: 'Playfield',
  players: ['Alice', 'Bob'], viewer: 0, scores: [0, 0], sets: [0, 0], set_number: 1, finished: false)
surface = GameSurfaces::AudioBallSurface.new(spec)
field = surface.fields.first
chat = EditBox.new('Chat', text: 'Keep this text', quiet: true)
root = GameRoomUI::Form.new([field, chat], quiet: true)
root.game_room_background_help_enabled = true
# Form#wait focuses a quiet form before its first native input snapshot.
# This step-by-step driver calls update directly, so reproduce that entry.
root.focus

3.times do
  driver.frame(root, driver.tap(0x26))
  assert(surface.input(root) == ['up'], 'real Button/Form lost a quick tap')
  assert(surface.input(root).empty?, 'same key was consumed twice')
end

driver.frame(root, driver.tap(0x09))
assert(root.fields[root.index].equal?(chat), 'native Tab did not focus chat')
driver.frame(root, [[0x26, true]], held: [0x26])
assert(surface.input(root).empty?, 'native chat arrow reached the game')
assert(chat.text == 'Keep this text', 'game input damaged chat contents')
driver.frame(root, [[0x10, true], [0x09, true]], held: [0x10, 0x09, 0x26])
assert(root.fields[root.index].equal?(field), 'native Shift+Tab did not return to game')
assert(surface.input(root).empty?, 'returning from chat replayed a held arrow')
driver.frame(root, [[0x10, false], [0x09, false]], held: [0x26])
assert(surface.input(root).empty?, 'chat held key became a fresh game press')
driver.frame(root, [[0x26, false], [0x26, true]], held: [0x26])
assert(surface.input(root) == ['up'], 'quick release/repress after returning from chat failed')
driver.frame(root, [[0x26, false]])

root.show_game_room_help
assert(root.game_room_background_help?, 'native help did not open')
driver.frame(root, [[0x28, true]], held: [0x28])
assert(surface.input(root).empty?, 'help navigation became a defense')
driver.frame(root, [[0x0D, true]], held: [0x0D, 0x28])
assert(!root.game_room_background_help?, 'native Enter did not close help')
assert(surface.input(root).empty?, 'help closing input reached the game')
driver.frame(root, [[0x0D, false]], held: [0x28])
assert(surface.input(root).empty?, 'held help arrow fired after closing')
driver.frame(root, [[0x28, false], [0x28, true]], held: [0x28])
assert(surface.input(root) == ['down'], 'fresh post-help key was lost')
driver.frame(root, [[0x28, false]])

settings = GameRoomUI::Form.new([ListBox.new(['Default', 'Alternative'], quiet: true)], quiet: true)
driver.frame(settings, [[0x28, true]], held: [0x28])
assert(surface.input(root).empty?, 'settings navigation reached the inactive game field')
field.focus
driver.frame(root, [[0x28, :repeat]], held: [0x28])
assert(surface.input(root).empty?, 'settings held key became a game press on return')
driver.frame(root, [[0x28, false], [0x28, true]], held: [0x28])
assert(surface.input(root) == ['down'], 'fresh post-settings release/repress was lost')
assert(chat.text == 'Keep this text', 'chat text changed across help/settings')
driver.frame(root, [[0x28, false]])
field.blur
assert(!GameRoomAudioBall::Keyboard.active?, 'native blur did not release capture')
driver.frame(root)
assert(GameRoomAudioBall::Keyboard.active?, 'quiet native Form#update did not restore capture')
driver.frame(root, [[0x44, true], [0x25, true], [0x53, true], [0x53, false]], held: [0x44, 0x25])
surface.input(root)
assert(surface.defense_input[:changes].map { |code, down, _| [code, down] } ==
  [[0x44, true], [0x25, true], [0x53, true], [0x53, false]], 'native quiet resume lost ordered defence transitions')
field.blur
puts 'PASS real native Audio Ball field: quick taps, Tab/Shift+Tab, chat text, F1 reader, settings, held-key guards and fresh return'
