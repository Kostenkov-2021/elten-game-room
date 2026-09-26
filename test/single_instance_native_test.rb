require_relative 'support/host_source'
require_relative '../lib/single_instance'
require 'timeout'

def assert(value, message); raise message unless value; end
def await_condition
  Timeout.timeout(4) { sleep(0.005) until yield }
end

module Log
  def self.debug(*); end
  def self.info(*); end
  def self.error(message); ($native_errors ||= []) << message; end
end
class Scene_Main; end
class Program; end
module Programs
  def self.handle_execution_error(*); false; end
end
require EltenTestHost.file('src/eapi/core/runtime.rb')
require EltenTestHost.file('src/eapi/common/threads.rb')

# Use ELTEN's real insert_scene, execution/finalization and thread switcher.
# Only its OS/keyboard/network frame is replaced by this cooperative wait.
class NativeSingleInstanceHost
  include EltenAPI
  include EltenAPI::Common
  def prepare_keyboard_scene_transition; end
  def loop_update(*)
    saved = $scene
    sleep(0.001) until Thread.current.equal?($currentthread)
    $scene = saved
    sleep(0.001)
  end
end

class NativeSingleInstanceProgram < Program
  attr_accessor :run
  attr_reader :entered, :finalized
  prepend GameRoomSingleInstance::EntryPoints
  def program_main
    @entered = true
    run&.call
  end
  def finalize(*)
    @finalized = true
    $scene = Scene_Main.new
  end
end

host = NativeSingleInstanceHost.new
$mainthread = $currentthread = Thread.current
$scene = owner = NativeSingleInstanceProgram.new
$subthreads, $scenes, $native_errors = [], [], []
other_gate = Queue.new
other_alive = Thread.new { other_gate.pop }
other_dead = Thread.new {}.tap(&:join)
$subthreads.concat([other_alive, other_dead])
switcher = Thread.new { host.send(:thr2) }
begin
  owner.run = lambda do
    6.times do
      discarded = NativeSingleInstanceProgram.new
      host.send(:insert_scene, discarded, true)
      await_condition do
        $currentthread.equal?($mainthread) && discarded.instance_variable_get(:@program_finalized) &&
          $subthreads.any? { |t| t.thread_variable_get(:game_room_redirected_launch) && !t.alive? }
      end
      assert(!discarded.entered && !discarded.finalized, 'Duplicate entered the program or cleaned up its owner')
      owner.cleanup_game_room_launches
      assert($subthreads == [other_alive, other_dead], 'Finished Game Room launch leaked, or another host window was removed')
      assert(GameRoomSingleInstance.instance_variable_get(:@active)[:program].equal?(owner), 'The original UI owner changed')
    end
    assert($native_errors.empty?, "Native dispatcher failed: #{$native_errors.inspect}")
  end
  owner.program_main
  owner.finalize
  assert(owner.entered && owner.finalized, 'Normal program lifetime was changed')

  # Never remove a still-running redirected launch, even while the host has
  # already put it in the window list. Reap it only on a later UI frame.
  gate = Queue.new
  pending = Thread.new do
    Thread.current.thread_variable_set(:game_room_redirected_launch, true)
    gate.pop
  end
  await_condition { pending.thread_variable_get(:game_room_redirected_launch) }
  $subthreads << pending
  GameRoomSingleInstance.discard_finished_launches
  assert($subthreads.include?(pending), 'A living launch was removed')
  gate << true
  pending.join
  # A worker is not allowed to mutate the host window list.
  Thread.new { GameRoomSingleInstance.discard_finished_launches }.value
  assert($subthreads.include?(pending), 'Cleanup ran outside the active UI thread')
  GameRoomSingleInstance.discard_finished_launches
  assert($subthreads == [other_alive, other_dead], 'Later UI cleanup did not remove exactly the finished launch')
ensure
  switcher.kill.join
  other_gate << true
  other_alive.join
end
puts 'PASS native single instance: six real host launches; no dead windows, duplicate UI or cleanup of foreign/live threads'
