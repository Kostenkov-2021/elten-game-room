require_relative 'support/audio_tutorial_native'
require_relative '../lib/single_instance'
require 'timeout'

# Real Core scene insertion/execution, parallel controller and native forms.
# Network, OS input and audio are absent. The outer pump below reproduces the
# host's cooperative pause/restore; it does not call another scene's main.
require EltenTestHost.file('src/eapi/core/runtime.rb')
require EltenTestHost.file('src/eapi/common/threads.rb')
Object.include(EltenAPI)

module Log
  def self.info(*); end
  def self.debug(*); end
end
module Programs
  def self.handle_execution_error(error, _scene)
    ($navigation_errors ||= []) << error
    false
  end
end
module SpeechOutput
  def self.speak_sequence(_sequence); end
end
class Scene_Main; end
class Program
  attr_reader :finalizations
  def finalize(_value = nil, reason: :normal)
    (@finalizations ||= []) << reason
    $scene = Scene_Main.new unless reason == :error
  end
end

class NavigationPump
  attr_reader :visits
  def initialize
    @steps, @visits = {}, []
  end
  def script(form, &operation)
    (@steps[form] ||= []) << operation
  end
  def tick(receiver)
    unless Thread.current.equal?($currentthread)
      saved = $scene
      sleep(0.005) until Thread.current.equal?($currentthread)
      $scene = saved
    end
    raise $navigation_errors.first unless $navigation_errors.empty?
    sleep(0.002)
    EltenAPI::KeyboardState.update(raw_state: "\0" * 256, events: [],
      now: Process.clock_gettime(Process::CLOCK_MONOTONIC),
      pressed_implies_held: false, synthesize_repeats: false)
    $input_frame_serial = $input_frame_serial.to_i + 1
    $keyboard_state_frame_serial = $input_frame_serial
    $keyboard_state_frame_thread = Thread.current
    $activecontrols = []
    return unless receiver.is_a?(Form) && receiver.instance_variable_get(:@wait)

    @steps[receiver]&.shift&.call
  end
end
def loop_update(*); $navigation_pump.tick(self); end
def prepare_keyboard_scene_transition; EltenAPI::KeyboardState.reset; end

class NavigationMessages
  attr_reader :completed
  def initialize(owner, outer_form)
    @owner, @outer_form = owner, outer_form
  end
  def main
    assert($scene.equal?(self), 'Inserted scene was not the active destination')
    assert(Thread.current.thread_variable_get(:elten_scene).equal?(self), 'Inserted scene lost its native context')
    owner = GameRoomSingleInstance.instance_variable_get(:@active)
    assert(owner[:program].equal?(@owner) && !owner[:thread].equal?(Thread.current), 'Covered Game Room lost its owner')
    assert(@outer_form.instance_variable_get(:@wait), 'Opening another scene ended the game form')
    text = EditBox.new('Native window', type: EditBox::Flags::ReadOnly, text: 'Other screen', quiet: true)
    form = Form.new([text], quiet: true)
    $navigation_pump.script(form) do
      $navigation_pump.visits << self.class
      form.resume
    end
    form.wait
    @completed = true
    $scene = Scene_Main.new
  end
end
class NavigationForum < NavigationMessages; end

class WidgetNavigationProgram < Program
  class << self; attr_accessor :scenario; end
  attr_reader :calls
  prepend GameRoomSingleInstance::EntryPoints
  def initialize; @calls = []; end
  def program_main; interact(:normal); end
  def open_widget_table(snapshot); interact(:table, snapshot); end
  def create_table_from_widget(slot = nil); interact(:create, slot); end
  def accept_invitation_from_widget; interact(:invitations); end
  def interact(*arguments)
    @calls << arguments
    self.class.scenario.call(self)
  end
end

$mainthread = $currentthread = Thread.current
$subthreads, $scenes, $navigation_errors, $activecontrols = [], [], [], []
$navigation_pump = NavigationPump.new
EltenAPI::KeyboardState.reset
original_threads = Thread.list
controller = Thread.new { Object.new.send(:thr2) }
begin
  Timeout.timeout(20) do
    # Both the game/chat form and another Game Room form remain owned by the
    # same native program. Switching out must neither rebuild nor resume them.
    WidgetNavigationProgram.scenario = lambda do |program|
      assert($scene.equal?(program), 'Game Room is still running inside the widget host scene')
      assert(Thread.current.thread_variable_get(:elten_scene).equal?(program), 'Game Room is still owned by Scene_Main')
      2.times do |screen|
        chat = EditBox.new('Chat', text: 'Zażółć gęślą jaźń', quiet: true)
        chat.index, chat.check = 4, 7
        board = ListBox.new(['Card A', 'Card B'], header: "Screen #{screen}", index: 1, quiet: true)
        form = GameRoomUI::Form.new([board, chat], program: program, index: 1, quiet: true)
        [NavigationMessages, NavigationForum].each do |destination|
          $navigation_pump.script(form) do
            target = destination.new(program, form)
            program.send(:insert_scene, target, true)
            until target.completed && Thread.current.equal?($currentthread)
              program.send(:loop_update, false)
            end
            assert($scene.equal?(program), 'Returning from the other window lost the game scene')
            assert(Thread.current.thread_variable_get(:elten_scene).equal?(program), 'Returning lost the program context')
            assert(form.index == 1 && board.index == 1, 'Native transition moved game/chat focus')
            assert(chat.text == 'Zażółć gęślą jaźń' && chat.index == 4 && chat.check == 7, 'Native transition lost the chat draft/selection')
          end
        end
        $navigation_pump.script(form) { form.resume }
        form.wait
      end
    end

    widget = WidgetNavigationProgram.new
    requests = [
      [:open_widget_table, [{id: 'selected-table'}], [:table, {id: 'selected-table'}]],
      [:create_table_from_widget, [nil], [:create, nil]],
      [:create_table_from_widget, [29], [:create, 29]],
      [:accept_invitation_from_widget, [], [:invitations]]
    ]
    requests.each do |entry, arguments, expected|
      $scene = main = Scene_Main.new
      Object.new.send(:with_scene_context, main) do
        widget.launch_game_room_entry(entry, *arguments)
        assert(widget.calls.empty?, 'Widget callback opened a long-lived Game Room form inline')
        assert(GameRoomSingleInstance.instance_variable_get(:@active).nil?, 'Widget callback took UI ownership')
      end
      launched = $scene
      assert(launched.is_a?(WidgetNavigationProgram) && !launched.equal?(widget), 'Native destination is not a fresh program')
      Object.new.send(:execute_scene_main, launched)
      assert(launched.calls == [expected], 'Native launch lost/repeated the widget action or opened the lobby')
      assert(launched.finalizations == [:normal] && widget.finalizations.nil?, 'Native launch lifetime/cleanup is incorrect')
      assert(GameRoomSingleInstance.instance_variable_get(:@active).nil?, 'Finished scene retained UI ownership')
      assert($scene.is_a?(Scene_Main), 'Finished scene did not return to ELTEN')
    end

    # The ordinary Programs-menu path must continue to use normal startup.
    $scene = ordinary = WidgetNavigationProgram.new
    Object.new.send(:execute_scene_main, ordinary)
    assert(ordinary.calls == [[:normal]] && ordinary.finalizations == [:normal], 'Ordinary launch changed')
    assert($navigation_pump.visits.size == 20, 'A Messages/forum scene did not actually run')
    assert($navigation_errors.empty?, 'Native controller raised an error')
    assert(Thread.current.thread_variable_get(:elten_scene).nil?, 'Scene context leaked after finalization')

    # Cancelling before joining, or failing during preparation, must release
    # the launch too. Neither case may finalize the reusable widget object.
    [:cancel, :error].each do |outcome|
      WidgetNavigationProgram.scenario = lambda do |_program|
        raise 'simulated preparation failure' if outcome == :error
        nil
      end
      $scene = Scene_Main.new
      widget.launch_game_room_entry(:accept_invitation_from_widget)
      pending = $scene
      begin
        Object.new.send(:execute_scene_main, pending)
        assert(outcome == :cancel, 'Core swallowed the entry failure')
      rescue RuntimeError => error
        raise unless outcome == :error && error.message == 'simulated preparation failure'
      end
      expected_reason = outcome == :error ? :error : :normal
      assert(pending.finalizations == [expected_reason], 'Core did not finalize the cancelled/failed entry once')
      assert(GameRoomSingleInstance.instance_variable_get(:@active).nil?, 'Cancelled/failed entry retained the UI owner')
      assert(pending.instance_variable_get(:@game_room_initial_entry).nil?, 'Cancelled/failed entry retained its request')
      assert(widget.finalizations.nil?, 'Cancelled/failed entry finalized the widget service')
      assert(Thread.current.thread_variable_get(:elten_scene).nil?, 'Cancelled/failed entry leaked scene context')
    end
  end
ensure
  controller.kill.join
  (Thread.list - original_threads).each { |thread| thread.kill.join }
end
puts 'PASS widget native navigation: four widget entries plus ordinary startup; 20 inserted windows; native forms preserve focus/draft; Core finalizes normal/cancelled/failed fresh launches'
