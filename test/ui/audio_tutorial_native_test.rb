require_relative "../support/audio_tutorial_native"
host = EltenTestHost.root

{
  ListBox.instance_method(:initialize) => 'ui/controls/list_box.rb',
  ListBox.instance_method(:update) => 'ui/controls/list_box.rb',
  Form.instance_method(:initialize) => 'ui/form.rb',
  Form.instance_method(:wait) => 'ui/form.rb',
  Form.instance_method(:resume) => 'ui/form.rb',
  EltenAPI::UI.instance_method(:key_pressed?) => 'ui/input.rb',
  EltenAPI::UI.instance_method(:key_first_pressed?) => 'ui/input.rb',
  EltenAPI::KeyboardState.method(:update) => 'eapi/keyboard.rb',
  EltenAPI::Speech.instance_method(:speak) => 'eapi/speech.rb'
}.each do |method, source|
  assert(File.expand_path(method.source_location.first) == File.join(host, 'src', source), "Not native host source: #{source}")
end
assert(GameRoomUI::Form.superclass == Form, 'Game Room form does not inherit the native host form')
assert(File.expand_path(GameRoomAudioTutorial.instance_method(:wait).source_location.first) ==
  File.expand_path("../../lib/audio_tutorial.rb", __dir__), 'Test replaced the actual tutorial wait')

SpeechOutput.reset
speak('First pending message')
speak('Second pending message', stop: false, break_sequence: false)
assert(SpeechOutput.queue.length == 2, 'Speech peripheral did not retain its queue')
speech_stop
assert(SpeechOutput.queue.empty?, 'Speech peripheral does not model destructive cancellation')
speak('Pending welcome')
speak('New focus')
assert(SpeechOutput.queue == ['New focus'], 'Native focus speech cannot expose a cut-off welcome')
SpeechOutput.reset
EltenAPI::KeyboardState.reset
$focus = false
speak('Rules menu item')

entries = [
  GameRoomAudioTutorial::Entry.new(label: 'First sound', asset: 'audio_ball_up'),
  GameRoomAudioTutorial::Entry.new(label: 'Second sound', asset: 'audio_ball_left')
]
program = NativeTutorialProgram.new
driver = NativeTutorialDriver.new(program, entries)
$native_tutorial_driver = driver
driver.frame('constructor focus and queued welcome', welcome: true)
driver.frame('first native wait frame', welcome: true)
driver.frame('second idle wait frame', welcome: true)
driver.frame('Down without autoplay', [0x28], index: 1)
driver.frame('Down released without autoplay')
driver.frame('Up without autoplay', [0x26], index: 0)
driver.frame('Up released without autoplay')
driver.activation('Enter', 0x0D, entries[0].asset)
driver.frame('Down stops the current sound', [0x28], index: 1, stop: true)
driver.frame('Down release keeps playback stopped')
driver.activation('Space', 0x20, entries[1].asset)
driver.frame('Escape', [0x1B])
driver.frame('native resume releases Escape', stop: true)

edit_boxes = 0
trace = TracePoint.new(:call) do |event|
  if event.method_id == :initialize && event.self.is_a?(EditBox)
    edit_boxes += 1
    raise 'Tutorial created an extra EditBox'
  end
end
trace.enable do
  GameRoomAudioTutorial.new(entries, program: program).wait
end
driver.finish
driver.form.fields.first.focus
assert(SpeechOutput.queue == ['Audio tutorial: Second sound'], 'Refocusing repeated the welcome or kept it as the list header')
assert(SpeechOutput.calls.count { |call| call.first.include?(WELCOME) } == 1, 'Navigation repeated the welcome')
assert(edit_boxes.zero?, 'Tutorial created an extra EditBox')
assert(program.plays.length == 4 && program.plays.all? { |entry| entry[2].close_count == 1 }, 'Escape leaked or double-closed an audio handle')
assert(driver.repeats.count(0x0D) == 4 && driver.repeats.count(0x20) == 4, 'The test did not exercise held Enter and Space repeats')
puts "PASS native audio tutorial: #{driver.checks} frames, #{program.plays.length} plays, #{driver.repeats.length} native repeats, #{edit_boxes} EditBoxes"
puts 'PASS Enter/Space press-hold-repeat-release-repress, native Up/Down without autoplay, queued welcome, Escape and sound cleanup'
puts "Host source: #{host}; peripherals and finite event loop only; no live ELTEN, NVDA or audio-device test"
