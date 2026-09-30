# Native EditBox/Form/KeyboardState and speech adapter, finite input peripherals.
require_relative "../support/parallel_scene_native"
require_relative "../../lib/game_background_presentation"

module EltenAPI::UI
  def loop_update(*args, **kwargs); super; end
end
# The host normally includes UI in its global API. This native-control harness
# replaces only its outer loop with finite input, so connect that same boundary.
Form.prepend(EltenAPI::UI)

class BackgroundTypingDriver < BackgroundHelpNativeDriver
  attr_accessor :characters
  def tick(form)
    active = form.equal?(root) && form.instance_variable_get(:@wait)
    super
    EltenWindow.test_character = characters.shift.to_s if active
  end
end

$mainthread = $currentthread = Thread.current
Thread.new do
  $currentthread = Thread.current
  EltenAPI::KeyboardState.reset
  SpeechOutput.reset
  driver = BackgroundTypingDriver.new
  text = 'Piszę podczas ruchu: ążźć, bez gubienia znaków.'
  driver.characters = text.chars
  driver.keys = text.length.times.map { |i| [i.even? ? 0x41 : 0x42] } + [[]]
  $native_tutorial_driver = driver
  field = EditBox.new('Wiadomość', text: '', quiet: true)
  form = Form.new([field], quiet: true)
  driver.root = form
  runner = Object.new
  runner.define_singleton_method(:covered?) { true }
  runner.define_singleton_method(:closed?) { false }
  screen = Object.new
  calls = 0
  screen.define_singleton_method(:present_background_session) do |_runner|
    raise 'Wrong presentation thread' unless Thread.current.equal?($currentthread)
    calls += 1
    speak('Zdarzenie gry.', stop: false, break_sequence: false) if calls == 5 || calls == 15
  end
  registration = GameRoomBackgroundPresentation.attach(screen, program: Object.new, runner: runner, key: [:typing])
  ticks = 0
  form.add_timer(FormTimer.new(0, repeat: true) { ticks += 1; form.resume if ticks > text.length })
  form.wait
  assert(calls >= text.length, 'Native outer loop did not drain presentation')
  assert(field.text == text, "Background speech lost input: #{field.text.inspect}")
  assert(field.index == text.length && field.check == field.index && form.index == 0, 'Background speech changed native caret/focus')
  messages = SpeechOutput.calls.select { |row| row.first == 'Zdarzenie gry.' }
  assert(messages.size == 2 && messages.all? { |row| row[1] == 0 && row[2] == false }, 'Speech did not use noninterrupting native output')
ensure
  registration&.close
  $currentthread = $mainthread
end.value
puts 'PASS native background presentation: Unicode typing, no lost characters, unchanged focus/caret and additive speech'
