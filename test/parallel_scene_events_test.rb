require_relative 'support/host_source'
require_relative 'support/ui'
require_relative 'support/log'
require_relative 'support/native_live_endpoint'

class Program
  def self.server_app(**_options); end
  def self.app_runtime; nil; end
end
module Session
  def self.name; 'Alice'; end
end
module EltenLink
  class Error < StandardError; end
  class Client; end
end
module EltenAPI
  module Tasks
    class Cancelled < StandardError; end
  end
end

require_relative '../__app'

def assert(value, message)
  raise message unless value
end

class Form
  # This fixture drives callbacks, not keyboard input. Global Ctrl+J must see
  # the same idle keyboard as the native-form companion test.
  def main_shortcut_pressed?(*, **); false; end

  def wait
    @wait = true
    Thread.current[:event_test_driver].call(self)
  ensure
    @wait = false
  end

  def update
    Thread.current[:event_test_native_update]&.call(self)
  end
end

def on_parallel_ui
  previous = $currentthread
  Thread.new do
    $currentthread = Thread.current
    yield
  ensure
    $currentthread = previous
  end.value
end

$mainthread = $currentthread = Thread.current
$activecontrols = []
app = EltenGameRoom.new
app.define_singleton_method(:live_sessions) { raise 'UI lazily created an endpoint' }
transport = GameRoomTransport.new(app)
app.instance_variable_set(:@transport, transport)
store = transport.instance_variable_get(:@live_store)
endpoint = NativeLiveEndpointFixture.build(context: app)
other_app = EltenGameRoom.new
other_endpoint = NativeLiveEndpointFixture.build(context: other_app)
store.instance_variable_set(:@endpoint, endpoint)
chat = EditBox.new('Chat', text: 'Do not lose this draft')
chat.index, chat.check = 7, 7
form = GameRoomUI::Form.new([ListBox.new(['Board'], header: 'Game'), chat], program: app, index: 1)
received = []
enqueue = ->(id) { endpoint.enqueue_callback(-> { received << id }) }
other_endpoint.enqueue_callback(-> { raise 'Dispatched another program endpoint' })

# This fails on the unfixed source: the main thread receives the stack, but
# dispatch:false while a parallel scene runs leaves the application asleep.
enqueue.call(:remote_move)
on_parallel_ui do
  Thread.current[:event_test_driver] = ->(current) { current.update }
  form.wait
end
assert(received == [:remote_move], 'Remote move remained queued in an active parallel Game Room')
assert(form.index == 1 && chat.text == 'Do not lose this draft' && chat.index == 7 && chat.check == 7,
  'Dispatch changed the chat, selection or focus')
assert(other_endpoint.instance_variable_get(:@callback_queue).length == 1, 'Another program queue was consumed')

# The normal main-thread path is still owned by ELTEN, not a second UI pump.
enqueue.call(:main_move)
Thread.current[:event_test_driver] = ->(current) { current.update }
form.wait
assert(received == [:remote_move], 'Fallback also dispatched on the main thread')
endpoint.dispatch_events
assert(received == [:remote_move, :main_move], 'Native dispatch no longer works')

# No form wait, no current scene, no program or no initialized/closed endpoint:
# never create a connection or consume a queue on behalf of a covered window.
enqueue.call(:after_return)
on_parallel_ui { form.update }
assert(received.length == 2, 'A non-waiting form dispatched events')
on_parallel_ui do
  Thread.current[:event_test_driver] = lambda do |current|
    active = $currentthread
    $currentthread = $mainthread
    current.update
    $currentthread = active
  end
  form.wait
end
assert(received.length == 2, 'Inactive UI thread dispatched events')
on_parallel_ui do
  Thread.current[:event_test_driver] = ->(current) { current.update }
  GameRoomUI::Form.new([], program: nil).wait
  GameRoomUI::Form.new([], program: EltenGameRoom.new).wait
  store.instance_variable_set(:@endpoint, nil)
  form.wait
  store.instance_variable_set(:@endpoint, endpoint)
  endpoint.instance_variable_set(:@closed, true)
  form.wait
  endpoint.instance_variable_set(:@closed, false)
  form.wait
end
assert(received == [:remote_move, :main_move, :after_return], 'Return did not deliver exactly once')

# Reentrant UI updates/callbacks cannot run the next callback inside the first.
order = []
endpoint.enqueue_callback(lambda do
  order << :first_begin
  form.update
  order << :first_end
end)
endpoint.enqueue_callback(-> { order << :second })
on_parallel_ui do
  Thread.current[:event_test_driver] = ->(current) { current.update }
  form.wait
end
assert(order == [:first_begin, :first_end, :second], 'Reentrant callbacks changed event order')

# A callback already entered by the native main dispatcher may be suspended
# at a scene switch. Respect its own dispatch guard; never wait for that UI
# thread while it is waiting for the parallel scene to finish.
entered, release = Queue.new, Queue.new
endpoint.enqueue_callback(-> { entered << true; release.pop; order << :native_end })
endpoint.enqueue_callback(-> { order << :after_native })
native = Thread.new { endpoint.dispatch_events }
entered.pop
on_parallel_ui do
  Thread.current[:event_test_driver] = ->(current) { current.update }
  form.wait
end
assert(order.last == :second, 'Parallel UI re-entered a native dispatcher')
release << true
native.value
assert(order.last(2) == [:native_end, :after_native], 'Native dispatcher did not finish in order')

# Use the real application -> transport -> store -> callback -> synchronizer
# route, including room/start/closure wake-ups rather than just ordinary moves.
# A visible room owns a subscription; without it retention correctly drops
# these synthetic signals because no room/session exists in this fixture.
room_feed = transport.subscribe_game_session(23)
endpoint.enqueue_callback(-> { store.send(:emit_change, 23, :game_started, 47) })
endpoint.enqueue_callback(-> { store.send(:emit_change, 23, :game, 47) })
endpoint.enqueue_callback(-> { store.send(:emit_change, 23, :table, nil) })
endpoint.enqueue_callback(-> { store.send(:emit_change, 23, :recovery, nil) })
on_parallel_ui do
  Thread.current[:event_test_native_update] = lambda do |_current|
    assert(transport.instance_variable_get(:@pending_game_starts)[23] == 47, 'Start missed the form timer')
    assert(transport.instance_variable_get(:@pending_game_changes).key?(47), 'Move missed the form timer')
    assert(transport.instance_variable_get(:@pending_table_changes)[23], 'Room event missed the form timer')
    assert(transport.instance_variable_get(:@pending_recoveries)[23], 'Recovery missed the form timer')
  end
  Thread.current[:event_test_driver] = ->(current) { current.update }
  form.wait
end
endpoint.enqueue_callback(-> { store.send(:emit_change, 23, :closed, nil) })
on_parallel_ui do
  Thread.current[:event_test_driver] = ->(current) { current.update }
  form.wait
end
assert(transport.instance_variable_get(:@pending_recoveries)[23] == :closed, 'Closure was not delivered')
room_feed.close

# A burst is bounded, then drains in order; native dispatch afterwards must
# have nothing left to replay. All entries use the real host event queue.
burst = []
100.times { |id| endpoint.enqueue_callback(-> { burst << id }) }
on_parallel_ui do
  Thread.current[:event_test_driver] = lambda do |current|
    current.update
    assert(burst.length.between?(1, 32), 'One frame was not bounded to 32 callbacks')
    10.times { current.update }
  end
  form.wait
end
endpoint.dispatch_events
assert(burst == (0...100).to_a, 'Burst lost, duplicated or reordered callbacks')

# Delivery precedes the existing form timers/replay. A help child must not
# double the per-frame budget when the parent updates it in the same frame.
help = GameRoomUI::Form.new([], program: app)
form.open_game_room_background_help(help, focus: false)
burst.clear
100.times { |id| endpoint.enqueue_callback(-> { burst << id }) }
on_parallel_ui do
  Thread.current[:event_test_driver] = ->(current) { current.update }
  form.wait
end
assert(burst.length.between?(1, 32), 'Background help doubled callback work per frame')
form.close_game_room_background_help(help, restore_focus: false)
endpoint.dispatch_events
assert(burst == (0...100).to_a, 'Closing help lost queued events')

# RC2's native dispatcher owns only endpoints whose client context is the
# active scene object, not all instances of the same application. Exercise it
# separately: the fallback tests above must still fail if Form stops draining.
assert(EltenAPI::LiveSessions.respond_to?(:dispatch_scene_events, true),
  'This native scene-delivery regression requires an ELTEN RC2-compatible host')
native_received = []
40.times { |id| endpoint.enqueue_callback(-> { native_received << id }) }
on_parallel_ui do
  Thread.current.thread_variable_set(:elten_scene, app)
  EltenAPI::LiveSessions.send(:dispatch_scene_events, app)
  assert(native_received.length.between?(1, 32), 'Native scene delivery exceeded its callback budget')
  10.times { EltenAPI::LiveSessions.send(:dispatch_scene_events, app) }
  assert(native_received == (0...40).to_a, 'Native scene delivery lost, duplicated or reordered callbacks')
  assert(other_endpoint.instance_variable_get(:@callback_queue).length == 1,
    'Native scene delivery consumed another instance of the same application')

  endpoint.enqueue_callback(-> { native_received << :while_covered })
  overlay = Object.new
  Thread.current.thread_variable_set(:elten_scene, overlay)
  EltenAPI::LiveSessions.send(:dispatch_scene_events, overlay)
  EltenAPI::LiveSessions.send(:dispatch_scene_events, app)
  assert(native_received.last == 39, 'Native dispatcher delivered a covered or mismatched scene')
  assert(store.dispatch_pending_events == 1 && native_received.last == :while_covered,
    'The covered-game callback was not available to its existing background drain')

  Thread.current.thread_variable_set(:elten_scene, app)
  EltenAPI::LiveSessions.send(:dispatch_scene_events, app)
  Thread.current[:event_test_driver] = ->(current) { current.update }
  form.wait
  assert(native_received == (0...40).to_a + [:while_covered], 'Returning to the game repeated callbacks')
end
assert(form.index == 1 && chat.text == 'Do not lose this draft' && chat.index == 7 && chat.check == 7,
  'Native scene delivery changed the chat, selection or focus')

# Single-instance cleanup also runs in a modal form. It does not wait for the
# root menu, consume an invitation there, dispatch twice or touch chat state.
dead_launch = Thread.new do
  Thread.current.thread_variable_set(:game_room_redirected_launch, true)
end.tap(&:join)
foreign_dead = Thread.new {}.tap(&:join)
$subthreads = [foreign_dead, dead_launch]
Thread.current[:event_test_driver] = ->(current) { current.update }
form.game_room_entry_boundary = false
form.wait
assert($subthreads == [foreign_dead], 'A modal form retained a finished launch or removed a foreign window')
assert(form.index == 1 && chat.text == 'Do not lose this draft' && chat.index == 7 && chat.check == 7,
  'Launch cleanup changed the modal form focus or chat')

puts 'Parallel-scene events passed: native endpoint constructor, fallback and RC2 scene delivery, covered drain, bounded ordered callbacks, chat and help'
