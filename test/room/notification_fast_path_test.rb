require_relative "../support/table_watch_runtime"

Notice2.class_eval do
  def presentation(**options); FakePresentation.new(options); end
end

class FastNoticeProgram < EltenGameRoom
  class << self
    attr_accessor :stored, :reads, :forbid_storage, :played, :fail_save
    def server_app_uuid; EltenGameRoom.server_app_uuid; end
    def read_json(_path, default:)
      raise "Notification blocked on settings storage" if forbid_storage
      self.reads = reads.to_i + 1
      Marshal.load(Marshal.dump(stored || default))
    end
    def sound_asset_path(_)
      raise "Managed notification needlessly materialized its sound on disk"
    end
    def play_sound_from_asset(name, volume:)
      played << [name, volume]
    end
  end
  def read_json(*args, **options); self.class.read_json(*args, **options); end
  def update_json(_path, default:)
    value = Marshal.load(Marshal.dump(self.class.stored || default))
    yield value
    raise IOError, "simulated failed save" if self.class.fail_save
    self.class.stored = value
    value
  end
end

program = FastNoticeProgram
program.stored = {"invitation_notifications" => "everyone", "table_watch_contacts_only" => false,
  "sound_volumes" => {"all" => 70, "notifications" => 50}}
program.played = []
program.normalized_settings # Startup, before the first notification/UI callback.
reads = program.reads
program.forbid_storage = true
now = 2_000_000_000
receiver = GameRoomTableWatch::Receiver.new(user: "Alice", games: ["uno"],
  uuid: program.server_app_uuid, clock: -> { now })
receiver.games = ["uno"]
program.instance_variable_set(:@table_watch_receiver, receiver)
notice = Notice2.new(id: 700, app_uuid: program.server_app_uuid,
  type: GameRoomTableWatch::TYPE, sender: "Bob", metadata: {
    "format" => 1, "game" => "uno", "table_id" => 15, "live_session_id" => "fast-notice-room",
    "created_at" => now, "expires_at" => now + 300})
presentation = program.map_notification(notice)
assert(program.played.empty?, "mapping played audio before DND/suppression")
program.notification_received(notice, presentation)
2.times { assert(presentation.sound.nil?, "host would play a second sound") }
assert(!presentation.default_suppressed && program.played == [["table_notice", 0.35]], "first table delivery changed")
100.times do
  mapped = program.map_notification(notice)
  program.notification_received(notice, mapped)
  assert(mapped.default_suppressed && mapped.sound.nil?, "duplicate was presented again")
  program.table_notice_visible?(notice)
end
invitation = program.map_notification(FakeNotification.new("Bob"))
program.notification_received(FakeNotification.new("Bob"), invitation)
invitation.sound
assert(program.played.last == ["notice", 0.35], "invitation lost its own sound or volume")
assert(program.reads == reads, "receipt/list/audio reopened settings")

# A successful explicit edit publishes the committed snapshot, across instances.
app = program.allocate
app.send(:update_game_room_settings) { |state| state["sound_volumes"]["notifications"] = 0 }
assert(program.normalized_settings["sound_volumes"]["notifications"] == 0, "saved mute did not reach callbacks")
before = program.played.size
invitation.sound
program.map_notification(FakeNotification.new("Bob")).sound
assert(program.played.size == before, "mute was not immediate")
app.send(:update_game_room_settings) do |state|
  state["invitation_notifications"] = "nobody"
  state["table_watch_contacts_only"] = true
end
assert(program.map_notification(FakeNotification.new("Bob")).default_suppressed, "saved invitation filter remained stale")
assert(program.normalized_settings["table_watch_contacts_only"], "saved table filter remained stale")
program.fail_save = true
begin
  app.send(:update_game_room_settings) { |state| state["invitation_notifications"] = "everyone" }
  raise "expected save failure"
rescue IOError
end
assert(program.normalized_settings["invitation_notifications"] == "nobody", "failed write changed effective privacy")
program.fail_save = false

# An explicit reload, unlike delivery, can reread disk and publish fresh values.
program.forbid_storage = false
program.stored["invitation_notifications"] = "everyone"
program.allocate.send(:game_room_settings, reload: true)
program.forbid_storage = true
assert(program.normalized_settings["invitation_notifications"] == "everyone", "explicit reload did not refresh the shared snapshot")
assert(program.reads == reads + 1, "save/reload performed extra reads")
now += 301
assert(program.map_notification(notice).default_suppressed, "expired notice became playable")
program.contacts_stop
puts "PASS notification fast path: no settings/asset disk access, delivery/list/duplicates, sound, committed filters/mute and explicit reload"
