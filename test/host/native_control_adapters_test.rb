require_relative '../support/background_help_native'
require_relative '../support/native_tasks'
require EltenTestHost.file('src/ui/controls/grid_box.rb')
GridBox = EltenAPI::Controls::GridBox
require_relative '../../lib/game_surfaces'
require_relative '../../lib/game_room_widget'
require_relative '../../lib/realtime/timer'

$mainthread = $currentthread = Thread.current
$activecontrols = []
driver = BackgroundHelpNativeDriver.new
$native_tutorial_driver = driver
EltenAPI::KeyboardState.reset

# Native event arguments, removal during dispatch, internal handlers/contexts,
# and the separately owned realtime timer all survive repeated screen binding.
field = GameSurfaces::RefreshAwareListBox.new(['One', 'Two'], quiet: true)
internal, screen = [], []
field.on(:test) { |arguments| internal << arguments }
field.bind_context { |menu| menu << :internal }
field.extend(GameRoomLayout::Bindings)
50.times do |generation|
  field.reset_bindings!
  field.on(:test) { |arguments| screen << [generation, arguments] }
  field.bind_context { |menu| menu << generation }
  field.trigger(:test, true, false, true)
  menu = []
  field.context(menu, false)
  assert(menu == [:internal, generation], 'Context bindings accumulated or removed internal commands')
end
assert(internal == [[true, false, true]] * 50 && screen == 50.times.map { |i| [i, [true, false, true]] },
  'Native event parameters changed or screen handlers accumulated')
field.reset_bindings!
field.on(:test) { field.reset_bindings! }
field.on(:test) { raise 'Removed callback ran during native dispatch' }
field.trigger(:test)
assert(field.instance_variable_get(:@events).length == 1, 'Removed registrations retained callbacks')

form = GameSurfaces::RefreshAwareForm.new([field], quiet: true)
form.extend(GameRoomLayout::Bindings)
driver.root = form
retained = EltenAPI::Controls::FormTimer.new(0, repeat: true) {}
ephemeral = EltenAPI::Controls::FormTimer.new(0, repeat: true) {}
form.add_timer(retained)
form.retain_binding_timer(retained)
form.add_timer(ephemeral)
form.reset_bindings!
assert(form.instance_variable_get(:@timers) == [retained], 'Rebinding removed realtime timer or kept screen timer')
form.delete_timer(retained)

# Native quiet reentry must suppress focus/marker, preserve flags and release
# the surface's one-shot suppression before the next actual keyboard movement.
frames = driver.frames
form.resume_for_refresh
assert(driver.frames == frames, 'Refresh resume consumed an input frame')
form.add_timer(EltenAPI::Controls::FormTimer.new(0, repeat: true) { form.resume_for_refresh })
field.suppress_next_focus!
SpeechOutput.reset
form.wait_without_announcement
assert(SpeechOutput.calls.empty? && form.instance_variable_get(:@quiet), 'Quiet wait announced or changed quiet mode')
field.focus
assert(!SpeechOutput.calls.empty?, 'Quiet reentry swallowed the next manual focus')
SpeechOutput.reset
form.wait
assert(!SpeechOutput.calls.empty?, 'Quiet wait disabled later ordinary focus')

# The native ListBox controls used by both adapters retain identity when a
# response arrives after the cursor moved, even if labels are identical.
Person = Struct.new(:participant, :label) { def to_s; label; end }
layout = GameRoomLayout::Screen.allocate
users = GameSurfaces::RefreshAwareListBox.new([], quiet: true)
layout.instance_variable_set(:@users, users)
alice, bob, carol = %w[Alice Bob Carol].map { |name| Person.new(name, 'Same label') }
layout.update_users([alice, bob, carol])
users.index = 1
layout.update_users([bob, carol, alice])
assert(users.index == 0 && layout.selected_participant == 'Bob', 'Participant identity was replaced by label/index')
layout.update_users([Person.new('BOB', 'Host'), carol, alice])
assert(users.index == 0 && users.options.first == 'Host', 'Role/case change moved participant selection')
layout.update_users([carol, alice])
assert(users.index == 0 && layout.selected_participant == 'Carol', 'Removed participant fallback changed')
layout.update_users([])
assert(layout.selected_participant.nil?, 'Empty list retained a participant')

rows = [1, 2, 3].map { |id| {id: id, label: 'Identical table names'} }
widget = GameRoomWidget::TableList.new(loader: -> { rows }, opener: ->(_) {},
  labeler: ->(row) { row[:label] }, id_for: ->(row) { row[:id] })
deliver = ->(values) { widget.send(:apply_result, values, nil, announce: false) }
deliver.call(rows)
widget.index = 2
deliver.call(rows.rotate(2))
assert(widget.index == 0 && widget.send(:selected_snapshot)[:id] == 3, 'Pending response reset native widget selection')
deliver.call([rows[0], rows[1]])
assert(widget.index == 0 && widget.send(:selected_snapshot)[:id] == 1, 'Removed table fallback changed')
deliver.call([])
assert(widget.send(:selected_snapshot).nil?, 'Empty widget retained stale table')
widget.close

# Native FormTimer owns stop/restart/removal; application clock gates immediate
# and start-to-start cadence, with no catch-up burst after a slow callback.
now, calls = 10.0, []
timer = GameRoomRealtime::Timer.new(clock: -> { now }, interval: 1) { calls << now; now += 0.4 }
timer.update
now = 10.9; timer.update
now = 11.0; timer.update
now = 40.0; timer.update
10.times { timer.update }
assert(calls == [10.0, 11.0, 40.0], 'First tick/cadence changed or missed frames were replayed')
timer.stop
now = 80.0; timer.update
assert(calls.length == 3, 'Stopped native timer still ran')
timer.start; timer.update
assert(calls.last == 80.0 && calls.length == 4, 'Restart did not tick immediately')
self_stopping = nil
self_stopping = GameRoomRealtime::Timer.new(clock: -> { now }) { calls << :stop; self_stopping.stop }
2.times { self_stopping.update }
assert(calls.count(:stop) == 1, 'Native repeat restarted a timer stopped in its callback')
form.add_timer(timer)
form.delete_timer(timer)
form.send(:update_timers)
assert(calls.count(80.0) == 1, 'Detached realtime timer ran')
puts 'PASS native control adapters: scoped registrations, quiet refresh, keyed people/widget selection and realtime cadence/lifecycle'
