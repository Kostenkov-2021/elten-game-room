require 'ostruct'
def assert(value, message); raise message unless value; end
module EltenAPI
  module Tasks
    class Cancelled < StandardError; end
    class TimedOut < Cancelled; end
    def self.run(**options)
      raise 'Check is not bounded/cancellable' unless options[:timeout] == 5.0 && options[:cancellable]
      yield(nil, Object.new.tap { |token| def token.raise_if_cancelled!; end })
    end
  end
  def alert(text); ($update_alerts ||= []) << text; end
end
module Log
  def self.warning(message); ($update_logs ||= []) << message; end
end
module Programs
  class << self
    attr_accessor :list, :runtime
    def with_runtime(value)
      previous = @runtime
      @runtime = value
      yield
    ensure
      @runtime = previous
    end
    def api_version_compatible?(value); value == '3.0.4'; end
    def platform_family; 'windows'; end
  end
end
module EltenLink
  module Apps
    class << self
      attr_accessor :packages, :failure, :calls
      def list(_client)
        self.calls = calls.to_i + 1
        raise failure if failure
        packages
      end
    end
  end
end
class Scene_Main; end
class Scene_Programs
  class << self; attr_accessor :install; end
  def install_remote_program(remote, ask:)
    raise 'Duplicate prompt' if ask
    self.class.install.call(remote)
  end
end
require_relative '../../lib/startup_update'
require_relative '../../lib/single_instance'
GameRoomLocalization.boot(settings: {'interface_language' => 'en'}, host_language: 'en')

class UpdateProgram
  include EltenAPI
  include GameRoomStartupUpdate::Entry
  prepend GameRoomSingleInstance::EntryPoints
  class << self; attr_accessor :app_info; end
  def self.app_uuid; 'game-room'; end
  self.app_info = OpenStruct.new(build_id: '241')
  attr_accessor :choice, :during_run
  attr_reader :calls, :prompts, :finalizations
  def initialize; @choice = true; @calls = []; @prompts = []; @finalizations = []; end
  def app_uuid; 'game-room'; end
  def platform_target; 'windows-x64'; end
  def elten_link; :client; end
  def confirm(text)
    @prompts << text
    yield if @choice
  end
  def program_main; @calls << [:program_main]; @during_run&.call; :opened; end
  def open_widget_table(row); @calls << [:table, row]; end
  def create_table_from_widget(slot = nil); @calls << [:create, slot]; end
  def accept_invitation_from_widget; @calls << [:picker]; end
  def notification_action(type, notification)
    return open_widget_table(notification) if type == :open_new_table
    @calls << [:notification, type, notification]
  end
  def insert_scene(scene, must); raise unless must; $scene = scene; end
  def finalize(value = nil, reason: :normal)
    @program_finalized = true
    @finalizations << reason
    raise 'cleanup failure' if @cleanup_failure
    $scene = Scene_Main.new
    value
  end
end
class UpdatedProgram < UpdateProgram
  self.app_info = OpenStruct.new(build_id: '242')
end
def remote(**changes)
  OpenStruct.new({id: 'game-room', build_id: '242', version: '2.0.5', elten_api_version: '3.0.4', platforms: ['all']}.merge(changes))
end
def reset_update
  GameRoomSingleInstance.instance_variable_set(:@active, nil)
  EltenLink::Apps.calls = 0
  EltenLink::Apps.failure = nil
  EltenLink::Apps.packages = [remote]
  Programs.list = [UpdateProgram]
  Programs.runtime = nil
  $update_alerts = []
end
reset_update
p = UpdateProgram.new
[remote(build_id: '241'), remote(build_id: '240'), remote(build_id: 'x242'), remote(build_id: nil),
 remote(id: 'different'), remote(elten_api_version: '9.0'), remote(platforms: ['linux'])].each do |entry|
  assert(GameRoomStartupUpdate.candidate(p, [entry]).nil?, 'Invalid/downgrade offer')
end
assert(GameRoomStartupUpdate.candidate(p, [remote(build_id: '1000'), remote]).build_id == '1000', 'Lexical build comparison')
assert(GameRoomStartupUpdate.candidate(p, [remote(id: 'GAME-ROOM')]), 'UUID comparison')

# Declining (including Escape, which leaves confirm's block uncalled) runs the
# original entry. Errors and timeout also fail open; an active UI never checks.
[nil, IOError.new('offline'), EltenAPI::Tasks::Cancelled.new('cancel'), EltenAPI::Tasks::TimedOut.new('timeout')].each do |failure|
  reset_update
  EltenLink::Apps.failure = failure
  p = UpdateProgram.new
  p.choice = false
  p.during_run = -> { UpdateProgram.new.program_main }
  assert(p.program_main == :opened, 'Decline/failure blocked opening')
  assert(EltenLink::Apps.calls == 1, 'Active launch checked again')
  assert(p.calls == [[:program_main]], 'Original entry was changed')
  assert(GameRoomSingleInstance.instance_variable_get(:@active).nil?, 'Opening leaked ownership')
end

routes = [[:program_main, [], [:program_main]], [:open_widget_table, [42], [:table, 42]],
  [:create_table_from_widget, [], [:create, nil]], [:create_table_from_widget, [29], [:create, 29]],
  [:accept_invitation_from_widget, [], [:picker]],
  [:notification_action, [:open_invitation, 9], [:notification, :open_invitation, 9]],
  [:notification_action, [:open_new_table, 42], [:table, 42]]]
routes.each do |entry, args, expected|
  [true, false, :error].each do |outcome|
    reset_update
    old = UpdateProgram.new
    old.__send__(entry, *args)
    assert(old.calls.empty? && old.prompts.size == 1, 'Game entered before update decision')
    assert(GameRoomSingleInstance.instance_variable_get(:@active)[:program].equal?(old), 'Update lost single-instance lease')
    old.finalize(nil, reason: entry == :notification_action ? :notification : :normal)
    bridge = $scene
    assert(bridge.is_a?(GameRoomStartupUpdate::InstallScene), 'Finalization swallowed update scene')
    assert(old.finalizations == [:notification], 'Update announced program closure')
    Scene_Programs.install = lambda do |_remote|
      assert(Programs.runtime.nil?, 'Self-unload inside executing runtime')
      assert(old.instance_variable_get(:@program_finalized), 'Unloading before finalization')
      duplicate = UpdateProgram.new
      duplicate.program_main
      duplicate.notification_action(:open_invitation, 7)
      duplicate.finalize
      assert(duplicate.calls.empty? && EltenLink::Apps.calls == 1, 'Duplicate update/entry while downloading')
      raise 'download error' if outcome == :error
      Programs.list = [UpdatedProgram] if outcome
      outcome
    end
    bridge.main
    reopened = $scene
    assert(reopened.class == (outcome == true ? UpdatedProgram : UpdateProgram), 'Reopened stale/wrong class')
    assert(reopened.instance_variable_get(:@game_room_initial_requests) == [[:notification_action, [:open_invitation, 7]]],
      'Entry received during downloading was lost or duplicated')
    reopened.program_main
    assert(reopened.calls == [expected], "Lost route #{entry}")
    assert(EltenLink::Apps.calls == 1, 'Reopen prompted again')
    assert(reopened.instance_variable_get(:@game_room_initial_requests).nil?, 'Deferred requests not consumed')
    assert(GameRoomSingleInstance.instance_variable_get(:@active).nil?, 'Reopen leaked lease')
    assert($update_alerts.size == (outcome == true ? 0 : 1), 'Failure feedback')
  end
end

# The fresh scene requested by a widget reaches the same guard, not an inline
# window. A finalization error must release the reserved instance as well.
reset_update
service = UpdateProgram.new
service.launch_game_room_entry(:create_table_from_widget, 8)
assert(EltenLink::Apps.calls.zero?, 'Widget checked inline')
scene = $scene
scene.program_main
assert(scene.prompts.size == 1 && service.prompts.empty?, 'Wrong widget check owner')
scene.instance_variable_set(:@cleanup_failure, true)
begin
  scene.finalize
rescue RuntimeError => error
  assert(error.message == 'cleanup failure', 'Unexpected cleanup error')
end
assert(GameRoomSingleInstance.instance_variable_get(:@active).nil?, 'Cleanup error leaked update lease')
puts 'PASS startup update: numeric policy, compatibility, decline/offline/cancel/timeout, seven routes x three outcomes, duplicate entry, reload and cleanup'
