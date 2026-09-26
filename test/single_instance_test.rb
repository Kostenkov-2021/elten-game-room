require_relative "../lib/single_instance"
require "timeout"

def assert(value, message); raise message unless value; end
class Scene_Main; end
class SingleEntryProbe
  attr_reader :calls, :finalized
  attr_accessor :run
  def initialize; @calls = []; end
  def program_main; @calls << :start; @run ? @run.call : :original_result; end
  def notification_action(*args)
    @calls << args
    return open_widget_table(args.last) if args.first == :open_new_table
    :notification
  end
  def open_widget_table(row); @calls << :widget; show_table_screen(row); end
  def create_table_from_widget(slot = nil); @calls << [:create, slot]; end
  def accept_invitation_from_widget; @calls << :invitation_picker; end
  def insert_scene(scene, must); @calls << [:launch, scene, must]; end
  def show_table_screen(row); @calls << [:table, row]; end
  def run_program_interface(row); @calls << [:interface, row]; end
  def finalize(*); @finalized = true; end
  prepend GameRoomSingleInstance::EntryPoints
end
owner, other = SingleEntryProbe.new, SingleEntryProbe.new
started, commands, completed = Queue.new, Queue.new, Queue.new
owner.run = -> do
  started << true
  loop do
    case commands.pop
    when :dispatch then owner.dispatch_game_room_entry; completed << true
    when :stop then break
    end
  end
  :owner_result
end
thread = Thread.new { owner.program_main }
Timeout.timeout(2) { started.pop }
20.times { assert(other.program_main == true, "Duplicate entry did not redirect") }
assert(other.calls.empty? && owner.calls == [:start], "Repeated launch rebuilt the interface")
assert($switchthread.equal?(thread) && $focus, "The native focus request targets the wrong UI thread")
other.finalize
assert(!other.finalized && owner.calls == [:start], "Discarded launch cleaned up the owner")
other.notification_action(:open_invitation, 9)
assert(other.calls.empty? && owner.calls == [:start], "An invitation ran in the wrong thread")
commands << :dispatch
Timeout.timeout(2) { completed.pop }
assert(owner.calls.last == [:open_invitation, 9], "The original action was not delegated")
commands << :stop
assert(Timeout.timeout(2) { thread.value } == :owner_result, "Entry return value changed")
assert(other.program_main == :original_result, "Closing did not release ownership")
other.finalize
assert(other.finalized, "The next real launch skipped cleanup")
owner.run = -> { raise "owner error" }
begin; owner.program_main; rescue RuntimeError => error; assert(error.message == "owner error", "Changed error"); end
assert(other.program_main == :original_result, "An error retained ownership")
# Nested widget requests unwind the old root instead of running two UI loops.
owner.run = -> do
  GameRoomSingleInstance.enter(other, :open_widget_table, [42]) { raise "wrong thread" }
  owner.dispatch_game_room_entry
  raise "old root was not unwound"
end
owner.program_main
assert(owner.calls.last == [:interface, 42], "Widget table switch did not reach the existing boundary")
assert(other.program_main == :original_result, "Widget switch leaked ownership")
# Stale ownership from a dead UI thread must not block a new invocation.
dead = Thread.new {}.tap(&:join)
GameRoomSingleInstance.instance_variable_set(:@active, {program: owner, thread: dead, requests: []})
assert(other.program_main == :original_result, "Dead owner was not discarded")
other.notification_action(:open_new_table, 91)
assert(other.calls.last == [:table, 91], "Notification's existing widget admission path was swallowed")

# A cold widget request only schedules a fresh native scene. It must not open
# a form inline, claim the main-screen callback as owner or finalize the widget.
widget = SingleEntryProbe.new
[
  [:open_widget_table, [53], [:widget, [:table, 53]]],
  [:create_table_from_widget, [nil], [[:create, nil]]],
  [:create_table_from_widget, [29], [[:create, 29]]],
  [:accept_invitation_from_widget, [], [:invitation_picker]]
].each do |entry, arguments, expected|
  widget.launch_game_room_entry(entry, *arguments)
  type, scene, must = widget.calls.last
  assert(type == :launch && must && !scene.equal?(widget), 'Widget did not schedule a fresh native program')
  assert(GameRoomSingleInstance.instance_variable_get(:@active).nil?, 'Scheduling claimed the widget callback as owner')
  assert(scene.calls.empty? && !scene.finalized && !widget.finalized, 'Scheduling executed/finalized a program')
  scene.program_main
  assert(scene.calls == expected, 'Native entry lost/repeated the requested action or opened the ordinary lobby')
  assert(scene.instance_variable_get(:@game_room_initial_entry).nil?, 'Launch request was retained for replay')
  scene.finalize
  assert(scene.finalized && !widget.finalized, 'Native cleanup finalized the reusable widget')
end

# Ownership may be acquired while a native launch is still queued. Keep the
# requested action, but redirect it instead of opening a second UI.
widget.launch_game_room_entry(:create_table_from_widget, 14)
pending = widget.calls.last[1]
owner.run = lambda do
  pending.program_main
  assert(pending.calls.empty?, 'Queued native launch opened a second interface')
  pending.finalize
  assert(!pending.finalized, 'Redirected native launch cleaned up the active program')
  owner.dispatch_game_room_entry
  assert(owner.calls.last == [:create, 14], 'Queued launch lost its initial action')
  before = widget.calls.length
  widget.launch_game_room_entry(:accept_invitation_from_widget)
  assert(widget.calls.length == before, 'Existing owner unnecessarily scheduled a new native scene')
  owner.dispatch_game_room_entry
  assert(owner.calls.last == :invitation_picker, 'Active widget action was not delegated')
end
owner.program_main
assert(GameRoomSingleInstance.instance_variable_get(:@active).nil?, 'Widget launch retained ownership')
puts "PASS single instance: focus, queued actions, return values, errors, cleanup and widget switch"
