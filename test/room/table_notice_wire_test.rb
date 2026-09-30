require_relative "../support/log"
require_relative "../../lib/table_watch"

def assert(value, message); raise message unless value; end

# LiveSessions uses opaque URL-safe IDs, not necessarily UUIDs. The earlier
# artificial UUID-only fixtures failed to represent an actual server room.
Notice = Struct.new(:id, :app_uuid, :type, :sender, :metadata, keyword_init: true)
now = 1_789_637_771
uuid = "468f59c5-c9d7-47cd-80f1-1a6fbfd1aa80"
metadata = JSON.parse('{"format":1,"game":"ninety_nine","table_id":1234567,"live_session_id":"9APCbq4RAfbGD7lGI--l1hmYmcQplXdP","created_at":1789637771,"expires_at":1789638071}')
notice = Notice.new(id: 42, app_uuid: uuid, type: GameRoomTableWatch::TYPE, sender: "Creator", metadata: metadata)
receiver = GameRoomTableWatch::Receiver.new(user: "Viewer", games: ["ninety_nine"], uuid: uuid, clock: -> { now })
receiver.games = ["ninety_nine"]
assert(receiver.visible?(notice), "real server session ID rejected, producing a blank notification")
assert(receiver.receive(notice) && receiver.received?(notice), "real ID was not recorded")
assert(receiver.visible?(notice) && !receiver.receive(notice), "repeat delivery changed visibility or repeated the alert")
duplicate = notice.dup
duplicate.id = 43
assert(!receiver.visible?(duplicate), "duplicate notice accepted")

["12345678-1234-1234-1234-123456789abc", "cP44FMhoJwxaQ80Rm02_JY0K9QxAsveo", "uEoTspHz_s-PSO-UVrMr8CaRSyVLTraP"].each do |id|
  variant = notice.dup
  variant.metadata = metadata.merge("live_session_id" => id)
  assert(receiver.visible?(variant), "valid opaque ID rejected: #{id}")
end
[nil, 123, [], {}, "", "x" * 257, "https://invalid.example/room", "../room", "room\n", "room room", "za\u017c\u00f3\u0142\u0107"].each do |id|
  variant = notice.dup
  variant.metadata = metadata.merge("live_session_id" => id)
  assert(!receiver.visible?(variant), "malformed session target accepted: #{id.inspect}")
end
receiver.resolve(metadata["live_session_id"])
assert(!receiver.visible?(notice), "joined table remained visible")
receiver = GameRoomTableWatch::Receiver.new(user: "Viewer", games: ["ninety_nine"], uuid: uuid, clock: -> { now })
now += 300
assert(!receiver.visible?(notice), "opaque ID bypassed expiration")
puts "Table notice wire format, validation, receipts, duplicates, join and expiry: OK"
