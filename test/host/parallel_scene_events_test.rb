require_relative '../support/host_source'
require_relative '../support/ui'
require_relative '../support/log'
require_relative '../support/native_live_endpoint'
require_relative '../support/native_scene_dispatch'
Object.include(NativeSceneDispatch)

class Program
  def self.server_app(**); end
  def self.app_runtime; nil; end
end
module Session
  def self.name; 'Alice'; end
end
module EltenLink
  class Error < StandardError; end
  class Client; end
end
require_relative '../../__app'

def assert(value, message = 'Assertion failed'); raise message unless value; end
class Form
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

def on_parallel_ui(scene, &block)
  previous = $currentthread
  Thread.new do
    $currentthread = Thread.current
    within_native_scene(scene, &block)
  ensure
    $currentthread = previous
  end.value
end

def frame(form)
  native_scene_frame
  form.update
end

$mainthread = $currentthread = Thread.current
$activecontrols = []
app = EltenGameRoom.new
app.define_singleton_method(:live_sessions) { raise 'UI lazily created an endpoint' }
transport = GameRoomTransport.new(app)
app.instance_variable_set(:@transport, transport)
store = transport.instance_variable_get(:@live_store)
endpoint = NativeLiveEndpointFixture.build(context: app)
other = NativeLiveEndpointFixture.build(context: EltenGameRoom.new)
store.instance_variable_set(:@endpoint, endpoint)
chat = EditBox.new('Chat', text: 'Do not lose this draft')
chat.index, chat.check = 7, 7
form = GameRoomUI::Form.new([ListBox.new(['Board'], header: 'Game'), chat], program: app, index: 1)
received = []
other.enqueue_callback(-> { raise 'Dispatched another program endpoint' })
endpoint.enqueue_callback(-> { received << :remote })
on_parallel_ui(app) do
  Thread.current[:event_test_driver] = ->(current) { frame(current) }
  form.wait
end
assert(received == [:remote], '3.0.4 native loop did not deliver the remote move')
assert(other.instance_variable_get(:@callback_queue).length == 1, 'Wrong program context')

# A form alone never drains: only the host loop may dispatch a visible scene.
# This includes main, parallel, nested help and modal updates.
endpoint.enqueue_callback(-> { received << :main })
Thread.current[:event_test_driver] = ->(current) { frame(current) }
form.wait
assert(received == [:remote], 'Parallel dispatcher also ran on main')
endpoint.dispatch_events
assert(received == [:remote, :main])
endpoint.enqueue_callback(-> { received << :return })
on_parallel_ui(app) do
  Thread.current[:event_test_driver] = ->(current) { 20.times { current.update } }
  form.wait
  within_native_scene(nil) { frame(form) }
  active = $currentthread
  begin
    $currentthread = $mainthread
    frame(form)
  ensure
    $currentthread = active
  end
  assert(received.length == 2, 'Form, absent scene or inactive thread drained callbacks')
  within_native_scene(Object.new) { frame(form) }
  assert(received.length == 2, 'Covered scene drained callbacks on UI')
  Thread.current[:event_test_driver] = ->(current) { frame(current) }
  form.wait
end
assert(received == [:remote, :main, :return])

order = []
endpoint.enqueue_callback(lambda do
  order << :begin
  frame(form)
  order << :end
end)
endpoint.enqueue_callback(-> { order << :second })
on_parallel_ui(app) { frame(form) }
assert(order == [:begin, :end, :second], 'Reentrant native dispatch reordered callbacks')
entered, release = Queue.new, Queue.new
endpoint.enqueue_callback(-> { entered << true; release.pop; order << :native_end })
endpoint.enqueue_callback(-> { order << :after_native })
native = Thread.new { endpoint.dispatch_events }
Timeout.timeout(3) { entered.pop }
on_parallel_ui(app) { frame(form) }
assert(order.last == :second, 'Parallel UI reentered a suspended native dispatcher')
release << true
native.value
assert(order.last(2) == [:native_end, :after_native])

feed = transport.subscribe_game_session(23)
[:game_started, :game, :table, :recovery].each do |kind|
  endpoint.enqueue_callback(-> { store.send(:emit_change, 23, kind, 47) })
end
on_parallel_ui(app) do
  Thread.current[:event_test_native_update] = lambda do |_|
    assert(transport.instance_variable_get(:@pending_game_starts)[23] == 47, 'Start missed timer')
    assert(transport.instance_variable_get(:@pending_game_changes).key?(47), 'Move missed timer')
    assert(transport.instance_variable_get(:@pending_table_changes)[23], 'Table missed timer')
    assert(transport.instance_variable_get(:@pending_recoveries)[23], 'Recovery missed timer')
  end
  frame(form)
end
endpoint.enqueue_callback(-> { store.send(:emit_change, 23, :closed, nil) })
on_parallel_ui(app) { frame(form) }
assert(transport.instance_variable_get(:@pending_recoveries)[23] == :closed)
feed.close

help = GameRoomUI::Form.new([], program: app)
form.open_game_room_background_help(help, focus: false)
burst = []
100.times { |id| endpoint.enqueue_callback(-> { burst << id }) }
on_parallel_ui(app) do
  Thread.current[:event_test_driver] = lambda do |current|
    frame(current)
    first = burst.length
    assert(first.between?(1, 32), 'A frame exceeded the native callback budget')
    10.times { current.update }
    assert(burst.length == first, 'Form/help supplied a second dispatch budget')
    100.times { frame(current) }
  end
  form.wait
end
form.close_game_room_background_help(help, restore_focus: false)
assert(burst == (0...100).to_a && endpoint.dispatch_events == 0, 'Lost/reordered/repeated burst')

# A covered game's existing worker/precommit drain is still required.
on_parallel_ui(Object.new) do
  endpoint.enqueue_callback(-> { received << :covered })
  frame(form)
  assert(received.last == :return)
  assert(store.dispatch_pending_events == 1 && received.last == :covered)
end
on_parallel_ui(app) { frame(form) }
assert(received == [:remote, :main, :return, :covered])

# Housekeeping stays on the existing form boundary, including modal cleanup.
maintained = 0
store.define_singleton_method(:maintain_pending_work) { maintained += 1 }
dead_launch = Thread.new { Thread.current.thread_variable_set(:game_room_redirected_launch, true) }.tap(&:join)
foreign = Thread.new {}.tap(&:join)
$subthreads = [foreign, dead_launch]
form.game_room_entry_boundary = false
Thread.current[:event_test_driver] = ->(current) { current.update }
form.wait
assert(maintained == 1 && $subthreads == [foreign], 'Housekeeping or modal launch cleanup was lost')
assert(form.index == 1 && chat.text == 'Do not lose this draft' && chat.index == 7 && chat.check == 7,
  'Native scene delivery changed draft, selection or focus')
puts 'PASS 3.0.4 native scene dispatch: visible/main/covered contexts, bounded callbacks, no second form drain, reentry, signals, help and cleanup'
