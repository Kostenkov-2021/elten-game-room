require_relative "../support/table_watch_runtime"

Notice2.class_eval do
  def presentation(**options); FakePresentation.new(options); end
end

settings = GameRoomPreferences.normalize(
  {"sound_volumes" => {"all" => 70, "notifications" => 50, "game" => 0}},
  EltenGameRoom::GAME_REGISTRY.ids
)
EltenGameRoom.define_singleton_method(:normalized_settings) { settings }
EltenGameRoom.define_singleton_method(:sound_asset_path) { |name| "C:/program-assets/#{name}.opus" }
played = []
EltenGameRoom.define_singleton_method(:play_sound_from_asset) { |name, volume:| played << [name, volume] }

now = 2_000_000_000
uuid = EltenGameRoom.server_app_uuid
receiver = GameRoomTableWatch::Receiver.new(user: "Alice", games: ["uno"], uuid: uuid, clock: -> { now })
EltenGameRoom.instance_variable_set(:@table_watch_receiver, receiver)
table = Notice2.new(id: 910, app_uuid: uuid, type: GameRoomTableWatch::TYPE, sender: "Bob",
  metadata: {"format" => 1, "game" => "uno", "table_id" => 8, "live_session_id" => "sound-test-room",
    "created_at" => now, "expires_at" => now + 300})
invitation = FakeNotification.new("Bob")

[invitation, table].each do |notification|
  presentation = EltenGameRoom.map_notification(notification)
  before = played.length
  assert(!presentation.default_suppressed && played.length == before, "mapping played or suppressed a valid notice")
  2.times { assert(presentation.sound.nil?, "native host would play a second sound") }
  assert(played.length == before + 1, "delivery failed to play exactly once")
end
assert(played == [["notice", 0.35], ["table_notice", 0.35]], "invitation/table sounds or their shared volume are wrong: #{played.inspect}")

# A delivered table is still deduplicated, and expired notices stay silent.
EltenGameRoom.notification_received(table, EltenGameRoom.map_notification(table))
before = played.length
duplicate = EltenGameRoom.map_notification(table)
EltenGameRoom.notification_received(table, duplicate)
assert(duplicate.default_suppressed && duplicate.sound.nil?, "duplicate notice was not suppressed")
now += 300
expired = EltenGameRoom.map_notification(table)
assert(expired.default_suppressed && expired.sound.nil?, "expired notice was not suppressed")
assert(played.length == before, "duplicate or expired table replayed a sound")
now -= 300

# Both assets belong to notifications, even when game sounds are muted.
%w[notice table_notice].each do |name|
  assert(GameRoomPreferences.sound_group(name) == "notifications", "#{name} uses game volume")
  assert(GameRoomSounds::ASSET_NAMES.include?(name), "#{name} is not registered")
  assert(File.binread(File.expand_path("../../Audio/#{name}.opus", __dir__), 64).include?("OpusHead"), "#{name} is not Opus")
end
manifest = JSON.parse(File.read(File.expand_path("../../manifest.json", __dir__), encoding: "UTF-8"))
%w[notice table_notice].each do |name|
  assert(manifest.dig("required_assets", "sounds").include?(name), "#{name} is missing from the manifest")
end

# No playback before host delivery (including DND), and a mute changed after
# mapping takes effect when the host requests the sound.
fresh = Notice2.new(**table.to_h.merge(id: 911, metadata: table.metadata.merge("live_session_id" => "sound-test-room-2")))
[invitation, fresh].each do |notification|
  settings["sound_volumes"]["all"] = 70
  settings["sound_volumes"]["notifications"] = 50
  mapped = EltenGameRoom.map_notification(notification)
  before = played.length
  settings["sound_volumes"]["notifications"] = 0
  mapped.sound
  assert(played.length == before, "notification mute at delivery was ignored")
  settings["sound_volumes"]["notifications"] = 50
  mapped = EltenGameRoom.map_notification(notification)
  settings["sound_volumes"]["all"] = 0
  mapped.sound
  assert(played.length == before, "master mute at delivery was ignored")
end
settings["sound_volumes"]["all"] = 70
settings["invitation_sounds"] = false
[invitation, fresh].each { |notification| assert(EltenGameRoom.map_notification(notification).sound.nil?, "disabled notification made a sound") }
puts "PASS separate invitation/table sounds, shared volume, delivery-only playback, duplicate/expired suppression and assets"
