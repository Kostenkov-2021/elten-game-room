require_relative "../support/parallel_scene_native"
require_relative "../support/native_live_endpoint"

program = Object.new
endpoint = NativeLiveEndpointFixture.build(context: program)
store = GameRoomLiveSessionStore.new(nil, endpoint_provider: -> { raise 'Unexpected lazy connection' })
store.instance_variable_set(:@endpoint, endpoint)
program.define_singleton_method(:maintain_game_room_scene) { store.maintain_pending_work }


$mainthread = $currentthread = Thread.current
$activecontrols = []
Thread.new do
  $currentthread = Thread.current
  EltenAPI::KeyboardState.reset
  driver = ParallelNativeDriver.new
  $native_tutorial_driver = driver
  text = 'Zażółć gęślą jaźń, bez Entera.'
  driver.characters = text.chars
  driver.keys = text.length.times.map { |i| [i.even? ? 0x41 : 0x42] } + [[]]
  driver.endpoint, driver.delivered = endpoint, []
  chat = EditBox.new('Chat', text: '', quiet: true)
  board = ListBox.new(['Board'], header: 'Game', quiet: true)
  form = GameRoomUI::Form.new([board, chat], program: program, index: 1, quiet: true)
  driver.root = form
  ticks = 0
  form.add_timer(FormTimer.new(0, repeat: true) do
    ticks += 1
    assert(driver.delivered.join == text[0, [ticks, text.length].min], 'Callback delayed past the UI timer')
    form.resume if ticks > text.length
  end)
  driver.within_native_scene(program) { form.wait }
  assert(chat.text == text, "Native typing lost/duplicated characters: #{chat.text.inspect}")
  assert(chat.index == text.length && chat.check == chat.index, 'Typing moved the caret incorrectly')
  assert(form.index == 1, 'Remote callbacks stole chat focus')
  assert(driver.delivered == text.chars, 'Queued callbacks were lost or duplicated')
  assert(endpoint.dispatch_events == 0, 'Native main path would repeat callbacks')
ensure
  $currentthread = $mainthread
end.value
puts 'PASS parallel native form: Unicode typing and callback delivery in the same frames; no Enter, focus jump or duplicate'
