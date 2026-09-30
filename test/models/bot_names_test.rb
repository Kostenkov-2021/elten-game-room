# encoding: UTF-8
require_relative "../support/native_room_harness"
require_relative "../../lib/room_presentation"
require_relative "../support/localization"

module Configuration
  def self.language; $bot_test_language; end
end

names = GameRoomBotNames
participants = GameRoomParticipants
assert(names::POLISH.length == 46 && names::ENGLISH.length == 26, "wrong supplied list sizes")
assert(names::NAMES.values.uniq.length == 72, "duplicate name catalog")
assert(names.name_for("pl25") == "Klara Sobieraj" && names.name_for("pl46") == "Pułkowniciowy", "New names lost their spelling or stable tokens")
assert(names.name_for("pl20") == "Maślana" && names.name_for("pl11") == "brzydkie Kaczątko", "Polish names changed")
assert(names.name_for("en03") == "Noob's spirit" && names.name_for("en17") == "Dr. jeckil", "English names/punctuation changed")
first = Object.new
def first.rand(_limit); 0; end
$bot_test_language = "pl-PL"
GameRoomTestLocalization.use_language($bot_test_language)
assert(names.interface_language == "pl", "Polish UI not detected")
assert(names.pick(occupied: ["JOLA"], random: first) == "pl02", "case-insensitive human collision ignored")
$bot_test_language = "en_US"
assert(names.interface_language == "pl", "host language changed the running Game Room translator")
GameRoomTestLocalization.use_language($bot_test_language)
assert(names.pick(random: first) == "en01", "English UI not selected")
$bot_test_language = "de"
GameRoomLocalization.boot(runtime: GameRoomTestLocalization.runtime($bot_test_language),
  host_language: "en", known_languages: [])
assert(names.pick(random: first) == "en01", "unsupported UI language has no English fallback")
names::NAMES.each do |token, name|
  id = participants.bot_id(123456789, 7, name_token: token)
  assert(id.ascii_only? && id.length < 64, "named seat exceeds actor limit")
  assert(participants.bot?(id) && !participants.human?(id), "named computer became human")
  assert(participants.bot_number(id) == 7 && participants.display_name(id) == name, "name/slot not decoded")
end
assert(!participants.bot?("bot:1:1:pl99") && !participants.bot?("bot:1:1:en01:extra"), "unknown/forged name code accepted")

$bot_test_language = "pl"
GameRoomTestLocalization.use_language($bot_test_language)
h = NativeRoomHarness.new(users: %w[jola Bob Carol])
owner = h.users.first
lobby = LobbyRepository.new(ProgramDouble.new(h.broker.endpoint(owner)), transport: h.transports.fetch(owner), server_tables: {})
added = []
%w[pl en pl].each do |language|
  $bot_test_language = language
  GameRoomTestLocalization.use_language(language)
  count_before = h.core.entries.count { |entry| entry["packet"]["kind"] == "room_state" }
  result = h.as(owner) { lobby.add_bot(h.table, snapshot: lobby.snapshot_for(h.table)) }
  assert(result.updated?, "add bot failed")
  bot = result.snapshot.bots.last
  added << bot
  assert(participants.bot_name_token(bot).start_with?(language), "pool differs from creator UI language")
  assert(!participants.display_name(bot).casecmp("jola").zero?, "bot duplicated a human name")
  assert(h.core.entries.count { |entry| entry["packet"]["kind"] == "room_state" } == count_before + 1, "name caused an extra room write")
end
expected_names = added.map { |bot| participants.display_name(bot) }
assert(expected_names.uniq == expected_names, "names repeated at a table")
%w[pl en].each do |language|
  $bot_test_language = language
  GameRoomTestLocalization.use_language(language)
  h.users.each do |user|
    3.times do
      view = h.transports.fetch(user).room_snapshot(h.table, force: true)
      assert(view[:bots] == added, "refresh/language/client changed a name")
    end
  end
end
removed = h.as(owner) { lobby.remove_bot(h.table, snapshot: lobby.snapshot_for(h.table), participant: added[1]) }
assert(removed.updated?, "could not remove selected computer")
remaining = removed.snapshot.bots
assert(remaining.map { |bot| participants.display_name(bot) } == [expected_names[0], expected_names[2]], "removing the middle bot removed/renamed someone else")
assert(remaining.map { |bot| participants.bot_number(bot) } == [1, 2], "slots not compacted")
h.users.each { |user| assert(h.transports[user].room_snapshot(h.table)[:bots] == remaining, "removal not synchronized") }

# Checkpoint before each new game must retain names after trimming room history.
h.start
assert(h.session["__players"] == h.users + remaining, "start lost named seats")
h.users.each do |user|
  assert(h.transports[user].room_snapshot(h.table, force: true)[:bots] == remaining, "room cleanup lost names")
end
bot = remaining.first
h.as(owner) do
  h.repositories[owner].append_events(session: h.session, sequence: 1,
    events: [GameRoomGames::EventCommand.new(action: "named_test", value: "ok")], actor: bot, controller: true)
end
h.assert_converged("named computer action", expected_count: 1)
assert(h.events(owner).first["actor"] == bot, "controlled action lost named actor")

# A remote reader joining after cleanup must receive names without asking
# the creator to draw again, including when it uses the other UI language.
h.add_client("Dave")
assert(h.join("Dave"), "late client cannot join")
assert(h.transports["Dave"].room_snapshot(h.table, force: true)[:bots] == remaining, "late join lost names")

store = h.transports.fetch(owner).instance_variable_get(:@live_store)
assert(store != nil, "missing native store")
validator = GameRoomLiveSessionStore::RecordValidator.new
[
  {"bot_count" => 1, "bot_names" => ["not-a-name"]},
  {"bot_count" => 2, "bot_names" => ["pl01", "pl01"]},
  {"bot_count" => 1, "bot_names" => []},
  {"bot_count" => 1, "bot_names" => {"0" => "pl01"}}
].each { |data| assert(!validator.send(:room_fields_valid?, data), "malformed name assignment accepted") }
assert(validator.send(:room_fields_valid?, {"bot_count" => 2, "bot_names" => ["pl01", "en03"]}), "valid assignment rejected")
assert(h.core.metadata["protocol"] == GameRoomLiveSessionStore::CURRENT_DISCOVERY_PROTOCOL && h.core.metadata["protocol"] >= 5, "old readers can mistake named bot actors for people")
puts "Bot names: 46 PL/26 EN, collisions, stable names, selected removal, shared clients, checkpoint, actors and validation: OK"
