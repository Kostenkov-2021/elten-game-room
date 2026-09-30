require_relative "../support/post_233_ping"
# These dispatch checks bypass Form#wait, which normally installs the bridge.
GameRoomUI.install_hotkeys

now = 0.0
worker = PingManualWorker.new
program = Object.new
service = GameRoomPing.new(program, worker: worker, clock: -> { now }, probe: -> { now += 0.042; true })
assert(service.request(program), 'first request rejected')
100.times { assert(!service.request(program), 'parallel ping requests') }
assert(service.poll(program) == nil && worker.starts == 1, 'ping did synchronous work or faked a result')
worker.finish
assert(service.poll(program) == 'HTTP ping: 42 ms.', 'RTT is not monotonic milliseconds')
assert(service.poll(program) == nil, 'ping repeated')
service.request(program); worker.finish; now += 20
assert(service.poll(program) == nil, 'stale result announced after leaving Game Room')

[-> { raise IOError, 'offline' }, -> { nil }, -> { false }].each do |probe|
  failure = GameRoomPing.new(program, worker: worker, clock: -> { now }, probe: probe)
  failure.request(program); worker.finish
  assert(failure.poll(program) == 'HTTP ping is unavailable.', 'error turned into a zero ping')
end
slow = GameRoomPing.new(program, worker: worker, clock: -> { now }, probe: -> { true })
slow.request(program); now += 7
assert(slow.poll(program) == 'HTTP ping is unavailable.', 'timeout missing')
assert(!slow.request(program), 'timed-out operation overlapped a retry')
worker.finish
assert(slow.request(program), 'finished timeout prevented retry')
worker.finish; slow.poll(program)

# Real host QuickActions dispatch: Ctrl+F4 only within Game Room. A form
# replaced by game refresh can deliver the same in-flight request once.
program.instance_variable_set(:@game_room_ping, service)
first = GameRoomUI::Form.new([ListBox.new(['play'], header: 'Game')], program: program)
second = GameRoomUI::Form.new([EditBox.new('Message', text: 'untouched')], program: program)
first.instance_variable_set(:@game_room_waiting, true)
second.instance_variable_set(:@game_room_waiting, true)
$activecontrols = [first]
native = EltenAPI::QuickActions.method(:hotkey_actions).super_method.call(16)
EltenAPI::QuickActions.hotkey_actions(16).each(&:call)
first.instance_variable_set(:@game_room_waiting, false)
worker.finish
$activecontrols = [second, second.fields.first]
before = $spoken_messages.length
2.times { second.update }
assert($spoken_messages.length == before + 1 && $spoken_messages.last == 'HTTP ping: 42 ms.', 'form refresh lost or repeated the result')
assert(second.fields.first.text == 'untouched', 'ping modified the editor')
$activecontrols = [Form.new([])]
assert(EltenAPI::QuickActions.hotkey_actions(16) == native, 'Ctrl+F4 escaped Game Room')

widget_active = true
widget = GameRoomWidget::TableList.new(loader: -> { raise 'ping refreshed tables' }, opener: ->(*) {},
  labeler: ->(*) {}, id_for: ->(*) {}, program: program, worker: PingManualWorker.new,
  active: -> { widget_active }, clock: -> { 0 })
widget.instance_variable_set(:@refresh_at, 100)
widget.define_singleton_method(:key_pressed?) { |_| false }
$activecontrols = [Form.new([]), widget]
EltenAPI::QuickActions.hotkey_actions(16).each(&:call)
worker.finish
before = $spoken_messages.length
2.times { widget.update }
assert($spoken_messages.length == before + 1, 'widget ping missing or repeated')
widget_active = false
assert(EltenAPI::QuickActions.hotkey_actions(16) == native, 'widget stole native shortcut outside its tab')

# Use the host's real typed System API against a fake client: no sockets.
load EltenTestHost.file("src/eltenlink/system.rb")
client = Object.new
calls = []
client.define_singleton_method(:api_data) do |*arguments, **options|
  calls << [arguments, options]
  now += 0.125
  {'time' => 12345}
end
program.define_singleton_method(:elten_link) { client }
api = GameRoomPing.new(program, worker: worker, clock: -> { now })
api.request(program); worker.finish
assert(api.poll(program) == 'HTTP ping: 125 ms.', 'typed host API not used for the probe')
assert(calls == [[['GET', '/api/v1/system/time', nil], {timeout: 5.0}]], 'unexpected API write, path or missing timeout')

# Real worker remains nonblocking while an artificial network read is held.
entered, release = Queue.new, Queue.new
thread_ids = []
async = GameRoomPing.new(program, probe: -> { thread_ids << Thread.current.object_id; entered << true; release.pop; true })
async.request(program)
Timeout.timeout(2) { entered.pop }
assert(thread_ids == [thread_ids.first] && thread_ids.first != Thread.current.object_id, 'probe ran on UI thread')
assert(async.poll(program) == nil, 'pending async operation blocked polling')
release << true
message = Timeout.timeout(2) { loop { value = async.poll(program); break value if value; Thread.pass } }
assert(message.start_with?('HTTP ping:'), 'worker result not delivered')
puts 'PASS ping: scoped real dispatcher/API, monotonic RTT, one background request, offline/timeout, stale suppression and refresh continuity'
