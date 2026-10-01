require_relative "game_room_localization"
require_relative "game_content"

# A voluntary, one-shot catalogue check before acquiring a table. The installer
# must run after Program#finalize, outside the runtime it is about to unload.
module GameRoomStartupUpdate
  CHECK_TIMEOUT = 5.0
  using GameRoomLocalization::Translations

  def self.numeric_build(value)
    text = value.to_s.strip
    text.match?(/\A[0-9]+\z/) ? Integer(text, 10) : nil
  end

  def self.candidate(program, packages)
    installed = numeric_build(program.class.app_info.build_id)
    return nil unless installed

    Array(packages).select do |remote|
      build = numeric_build(remote.build_id)
      remote.id.to_s.casecmp?(program.app_uuid.to_s) && build && build > installed &&
        Programs.api_version_compatible?(remote.elten_api_version) &&
        !(Array(remote.platforms) & ["all", "universal", "*", Programs.platform_family,
          program.__send__(:platform_target)]).empty?
    end.max_by { |remote| numeric_build(remote.build_id) }
  end

  def self.check(program)
    EltenAPI::Tasks.run(title: GameRoomContent.utf8(_("Checking for Power Games updates")),
      timeout: CHECK_TIMEOUT, cancellable: true, show_after: 0.5) do |_progress, token|
      token.raise_if_cancelled!
      candidate(program, EltenLink::Apps.list(program.__send__(:elten_link)))
    end
  rescue StandardError => error
    # Offline, cancellation and catalogue failure never prevent opening the
    # installed build. There is no periodic retry during a game.
    Log.warning("Game Room update check skipped: #{error.class}: #{error.message}") if defined?(Log)
    nil
  end

  module Entry
    using GameRoomLocalization::Translations

    def prepare_game_room_update(entry, arguments)
      return false if @game_room_update_checked
      @game_room_update_checked = true
      remote = GameRoomStartupUpdate.check(self)
      return false unless remote

      confirmed = false
      message = GameRoomContent.utf8(_("A new version of Power Games is available (%{version}, build %{build}). Would you like to update now? Choosing No opens the installed version.")) % {
        version: GameRoomContent.utf8(remote.version.to_s), build: GameRoomContent.utf8(remote.build_id.to_s)
      }
      confirm(message) { confirmed = true }
      return false unless confirmed

      @game_room_update_scene = InstallScene.new(self, remote, [entry, arguments],
        GameRoomContent.utf8(_("The update was not installed. Opening the installed version of Power Games.")),
        GameRoomContent.utf8(_("Power Games could not be reopened. Please open it from Programs.")))
      true
    end
  end

  class InstallScene
    include EltenAPI

    def initialize(program, remote, request, failure_message, reopen_message)
      @program, @remote, @request = program, remote, request
      @uuid = program.app_uuid.to_s
      @failure_message, @reopen_message = failure_message, reopen_message
    end

    def main
      # Core/NotificationActionScene has already finalized the old Program.
      # Do not run installation on a worker or underneath a live program call:
      # the host deliberately refuses to unload its executing runtime.
      raise "Game Room update entered before finalization" unless @program.instance_variable_get(:@program_finalized)
      installed = Programs.with_runtime(nil) do
        installer = Scene_Programs.new
        installer.__send__(:install_remote_program, @remote, ask: false)
      end
      alert(@failure_message) unless installed
      reopen
    rescue StandardError => error
      Log.warning("Game Room startup update failed: #{error.class}: #{error.message}") if defined?(Log)
      alert(@failure_message)
      reopen
    ensure
      GameRoomSingleInstance.finish_update(@program)
      @program = @remote = @request = nil
    end

    private

    def reopen
      # Resolve the new class, not the old one held by the launch/notification.
      klass = Programs.list.find { |entry| entry.app_uuid.to_s.casecmp?(@uuid) }
      requests = GameRoomSingleInstance.finish_update(@program)
      unless klass
        alert(@reopen_message)
        $scene = Scene_Main.new
        return
      end
      scene = klass.new
      scene.instance_variable_set(:@game_room_update_checked, true)
      scene.instance_variable_set(:@game_room_initial_entry, @request)
      scene.instance_variable_set(:@game_room_initial_requests, requests)
      $scene = scene
    end
  end
end
