require_relative "../support/host_source"
require_relative "../support/ui"
require EltenTestHost.file("src/eapi/quickactions.rb")

# The original bridge remains on the host singleton after an application
# reload. It predates Ctrl+F4 and only recognizes help and volume shortcuts.
target = EltenAPI::QuickActions.singleton_class
legacy = Module.new do
  define_method(:hotkey_actions) do |key|
    form = $activecontrols.to_a.reverse.find do |control|
      control.respond_to?(:game_room_hotkeys_active?) && control.game_room_hotkeys_active?
    end
    if form != nil && [1, 2, 3, -2, -3].include?(key)
      action = form.game_room_hotkey_action(key)
      return [action] if action != nil
    end
    super(key)
  end
end
target.prepend(legacy)
target.instance_variable_set(:@game_room_dispatch_bridge, true)

# Load only the shared host fixture, then upgrade the already installed bridge.
require_relative "../support/post_233_ping"
GameRoomUI.install_hotkeys

# Exercise the real native conversion Ctrl+F4 -> 16, not only calls to
# hotkey_actions with an already decoded number. No keyboard or network I/O.
load EltenTestHost.file("src/ui/input.rb")
module GlobalMenu
  def self.opened?; false; end
end
input = Object.new.extend(EltenAPI::UI)
input.define_singleton_method(:consume_native_main_menu_request) { false }
input.define_singleton_method(:keyprocs_idle_frame?) { false }
input.define_singleton_method(:keyboard_modifier_state?) { |*| false }
input.define_singleton_method(:key_pressed?) { |_| false }
input.define_singleton_method(:key_first_pressed?) { |_| false }
input.define_singleton_method(:key_any_pressed?) { false }
held = [:main_modifier, :control]
first = true
input.define_singleton_method(:modifier_held?) { |key| held.include?(key) }
input.define_singleton_method(:raw_key_held?) { |key| key == :key_shift && held.include?(:shift) }
input.define_singleton_method(:raw_key_first_pressed?) { |key| first && key == 0x73 }

worker = PingManualWorker.new
program = Object.new
volume_calls = []
program.define_singleton_method(:adjust_game_room_volume) { |*arguments, **options| volume_calls << [arguments, options] }
service = GameRoomPing.new(program, worker: worker, probe: -> { true }, clock: -> { 0.0 })
program.instance_variable_set(:@game_room_ping, service)
chat = EditBox.new('Chat', text: 'Zażółć')
chat.index, chat.check = 2, 4
form = GameRoomUI::Form.new([chat], program: program)
form.instance_variable_set(:@game_room_waiting, true)
$activecontrols = [form, chat]
input.send(:keyprocs)
assert(worker.starts == 1, 'native Ctrl+F4 was not dispatched after reload')
worker.finish
form.update
assert($spoken_messages.last == 'HTTP ping: 0 ms.', 'ping transport missing')
first = false
input.send(:keyprocs)
assert(worker.starts == 1, 'held function key repeated the probe')
first = true
[[], [:main_modifier, :control, :shift], [:option, :main_modifier, :control]].each do |modifiers|
  held = modifiers
  input.send(:keyprocs)
end
assert(worker.starts == 1 && volume_calls.empty?, 'plain/Shift/Alt F4 was captured as ping or volume')
assert([chat.text, chat.index, chat.check] == ['Zażółć', 2, 4], 'ping changed chat text or selection')

native = target.instance_method(:hotkey_actions).bind(EltenAPI::QuickActions).super_method.super_method
[4, 13, -16, 28].each do |key|
  assert(EltenAPI::QuickActions.hotkey_actions(key) == native.call(key), 'unrelated native shortcut intercepted')
end
$activecontrols = [Form.new([])]
assert(EltenAPI::QuickActions.hotkey_actions(16) == native.call(16), 'ping leaked outside Game Room')
before = target.ancestors.length
20.times { GameRoomUI.install_hotkeys }
assert(target.ancestors.length == before, 'bridge accumulated on repeat installation')
puts 'PASS ping after legacy bridge: native key dispatch, exact modifiers, native fallback, chat preserved, idempotent upgrade'
