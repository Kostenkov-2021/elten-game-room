require_relative '../support/table_watch_runtime'
require_relative '../support/app_notification_models'
require_relative '../support/native_notification_mute'

class NativeDeferredMuteProgram < EltenGameRoom
  class << self
    attr_accessor :effective_settings, :captured_sounds, :test_cache
    def normalized_settings; effective_settings; end
    def contacts_cache; test_cache; end
    def sound_asset_path(name); name; end
    def play_sound_from_asset(name, volume:); captured_sounds << [name, volume]; end
  end
end

program = NativeDeferredMuteProgram
program.effective_settings = GameRoomPreferences.normalize(
  {'invitation_notifications' => 'contacts', 'invitation_sounds' => true},
  EltenGameRoom::GAME_REGISTRY.ids)
known = nil
cache = Object.new
cache.define_singleton_method(:include?) { |_| known }
cache.define_singleton_method(:revision) { 0 }
program.test_cache = cache
program.instance_variable_set(:@contacts_cache, cache)
program.instance_variable_set(:@contact_revision, 0)
previous_callback, previous_legacy = $notifications_callback, $donotdisturb
begin
  # Deliberately disagree with the obsolete global: the native API alone
  # must decide whether the deferred delivery is audible.
  (0..3).each do |mode|
    GameRoomTest::NativeNotificationMute.with_mode(mode) do
      $donotdisturb = [0, 2].include?(mode)
      queue = GameRoomContacts::Pending.new
      program.instance_variable_set(:@contact_pending, queue)
      program.captured_sounds = []
      delivered = []
      $notifications_callback = ->(event) { delivered << event }
      known = nil
      notice = Programs::AppNotification.new(id: 1900 + mode,
        app_uuid: program.server_app_uuid, type: 'game_room.invitation', sender: 'Bob',
        created_at: Time.now.to_i, metadata: {'sender' => 'Bob', 'game' => 'uno',
          'table_name' => 'Offline test', 'table_id' => 71, 'invitation_id' => 81,
          'live_session_id' => 'offline-test', 'expires_in' => 300})
      presentation = program.map_notification(notice)
      program.notification_received(notice, presentation)
      assert(presentation.default_suppressed? && queue.entries.size == 1,
        'Unknown contacts did not defer the notification')
      assert(delivered.empty? && program.captured_sounds.empty?, 'Deferral played sound or speech')

      known = true
      program.contacts_tick
      expected = EltenAPI::UI.notifications_muted? ? 0 : 1
      assert(delivered.size == expected && program.captured_sounds.size == expected,
        "Deferred notification ignored native quiet mode #{mode}")
      assert(queue.entries.empty?, 'Settled notification remained queued')

      # Neither unmuting nor a repeated host receipt is another delivery.
      GameRoomTest::NativeNotificationMute.with_mode(0) do
        3.times { program.contacts_tick }
        duplicate = program.map_notification(notice)
        program.notification_received(notice, duplicate)
        assert(duplicate.default_suppressed?, 'Native redelivery repeated a deferred notification')
        assert(delivered.size == expected && program.captured_sounds.size == expected,
          'Unmuting replayed a previously muted notification')
      end
    end
  end
ensure
  $notifications_callback, $donotdisturb = previous_callback, previous_legacy
end

puts 'PASS Deferred contact notification follows all four native quiet modes, ignores the obsolete global and never replays on unmute'
