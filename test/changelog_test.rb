require_relative "support/ui"
require_relative "support/log"

class Program
  def self.server_app(**_options); end
  def self.app_runtime; nil; end

  def self.test_json
    @test_json ||= {}
  end

  def read_json(path, default:)
    self.class.test_json.fetch(path, default)
  end

  def update_json(path, default:)
    value = self.class.test_json.fetch(path, default)
    yield(value)
    self.class.test_json[path] = value
  end
end

module Session
  def self.name; "Alice"; end
end

module EltenLink
  class Error < StandardError; end
  class Client; end
  module Contacts; end
end

module EltenAPI
  module LiveSessions
    class Error < StandardError; end
    class TimeoutError < Error; end
    class SessionClosed < Error; end
    class StackFull < Error; end
  end

  module Tasks
    class Cancelled < StandardError; end
  end
end

require_relative "../__app"

def assert(condition, message)
  raise message if !condition
end

entries = GameRoomChangelog::ENTRIES
first_install = GameRoomChangelog.pending_entries(nil, 222, entries: entries)
assert(first_install.map(&:build) == [222], "first installation did not show only the current build")
missed = GameRoomChangelog.pending_entries(220, 222, entries: entries)
assert(missed.map(&:build) == [222, 221], "missed updates were not shown newest first")
assert(GameRoomChangelog.pending_entries(223, 222, entries: entries).empty?, "a downgrade reopened an old changelog")
assert(GameRoomChangelog.pending_entries(nil, 220, entries: entries).empty?, "first installation showed an older build")
assert(GameRoomChangelog.available_entries(221, entries: entries).map(&:build) == [221], "future entries appeared in the manual list")

lines = GameRoomChangelog.list_items(first_install)
assert(lines.first == "Version 1.1.8, build 222", "the current build heading is incorrect")
assert(lines.drop(1) == first_install.first.changes, "the build number is repeated for every change")
missed_lines = GameRoomChangelog.list_items(missed)
assert(missed_lines.count { |line| line.start_with?("Version ") } == 2, "missed builds do not have one heading each")
assert(missed_lines.first == "Version 1.1.8, build 222", "missed builds are not shown newest first")

resumes = 0
captured_form = nil
Form.class_eval do
  define_method(:resume) { resumes += 1 }
  alias_method :changelog_original_wait, :wait
  define_method(:wait) do
    captured_form = self
    accept_button.trigger(:press)
  end
end
GameRoomScreens::Changelog.new(["Change one", "Change two"]).wait
assert(captured_form.fields.length == 2, "the changelog is not a single list with a hidden close action")
assert(captured_form.fields.first.options == ["Change one", "Change two"], "the changelog changed its rows")
assert(captured_form.accept_button.equal?(captured_form.cancel_button), "Enter and Escape do not close the same list")
assert(captured_form.hidden_controls.include?(captured_form.accept_button), "the close action became an extra visible field")
assert(resumes == 1, "Enter on the changelog list did not close it")
Form.class_eval do
  alias_method :wait, :changelog_original_wait
  remove_method :changelog_original_wait
end

shown = []
GameRoomScreens::Changelog.define_singleton_method(:new) do |items, **_options|
  shown << items
  Object.new.tap { |screen| screen.define_singleton_method(:wait) { true } }
end

app = EltenGameRoom.new
app.send(:show_update_changelog)
state = app.read_json(GameRoomChangelog::STORAGE_FILE, default: {})
current_entry = GameRoomChangelog::ENTRIES.find { |entry| entry.build == EltenGameRoom::GAME_ROOM_BUILD_ID }
assert(current_entry.version == EltenGameRoom::GAME_ROOM_VERSION, "current changelog version differs from runtime")
entry_226 = entries.find { |entry| entry.build == 226 }
assert(entry_226.version == "1.1.10" && entry_226.changes.length == 9, "build 226 does not contain the agreed release notes")
assert(entry_226.changes.last.include?("empty notification entry"), "build 226 lacks invitation history correction")
assert(GameRoomChangelog.pending_entries(225, 226).map(&:build) == [226], "build 226 repeats already-read changes")
entry_224 = entries.find { |entry| entry.build == 224 }
entry_225 = entries.find { |entry| entry.build == 225 }
assert(entry_225.changes.take(3) == entry_224.changes.take(3), "build 225 dropped the agreed previous changelog")
assert(entry_225.changes.last.include?("announced during a bot's turn"), "build 225 does not explicitly mention Makao during bot turns")
expected_current_rows = current_entry.changes.length + 1
assert(shown.length == 1 && shown.first.length == expected_current_rows, "the current changelog was not shown on first launch")
assert(state[GameRoomChangelog::LAST_SEEN_BUILD_KEY] == EltenGameRoom::GAME_ROOM_BUILD_ID, "closing the changelog did not mark the build as read")
reopened_app = EltenGameRoom.new
reopened_app.send(:show_update_changelog)
assert(shown.length == 1, "the changelog was shown again after reopening Game Room")
reopened_app.send(:show_changelog)
assert(shown.length == 2, "the changelog could not be opened manually")

assert(EltenGameRoom::MAIN_OPTIONS.last == "What's new", "the main menu has no What's new entry")
opened = 0
app.define_singleton_method(:show_changelog) { opened += 1 }
app.send(:open_main_option, EltenGameRoom::MAIN_OPTIONS.length - 1)
assert(opened == 1, "the main menu entry does not open the changelog")

translations = JSON.parse(File.read(File.expand_path("../locale/changelog-after-221-pl.json", __dir__), encoding: "UTF-8"))
mo = File.binread(File.expand_path("../locale/PL.mo", __dir__))
count, originals, localized = mo.byteslice(8, 12).unpack("V3")
catalog = count.times.to_h do |index|
  source_length, source_offset = mo.byteslice(originals + index * 8, 8).unpack("V2")
  value_length, value_offset = mo.byteslice(localized + index * 8, 8).unpack("V2")
  [
    mo.byteslice(source_offset, source_length).force_encoding("UTF-8"),
    mo.byteslice(value_offset, value_length).force_encoding("UTF-8")
  ]
end
translations.each do |source, translation|
  assert(catalog[source] == translation, "uncompiled changelog translation: #{source}")
end
assert(catalog[entry_225.changes.last].to_s.include?("powiedzieć również w trakcie tury bota"),
  "the Polish changelog does not explicitly mention Makao during bot turns")
release_translations = JSON.parse(File.read(File.expand_path("../locale/changelog-build-226-pl.json", __dir__), encoding: "UTF-8"))
assert(release_translations.keys == entry_226.changes, "release notes and Polish translation differ")
release_translations.each do |source, translation|
  assert(catalog[source] == translation, "uncompiled build 226 translation: #{source}")
end

entry_227 = entries.find { |entry| entry.build == 227 }
release_2 = JSON.parse(File.read(File.expand_path('../locale/changelog-build-227-pl.json', __dir__), encoding: 'UTF-8'))
assert(entry_227.version == '2.0' && entry_227.changes == release_2.keys, '2.0 changelog and translations differ')
release_2.each { |source, translation| assert(catalog[source] == translation, "uncompiled 2.0 translation: #{source}") }
assert(GameRoomChangelog.pending_entries(226, 227).map(&:build) == [227], '2.0 duplicates old build headings')

entry_228 = entries.find { |entry| entry.build == 228 }
release_228 = JSON.parse(File.read(File.expand_path("../locale/changelog-build-228-pl.json", __dir__), encoding: "UTF-8"))
assert(entry_228.version == "2.0" && entry_228.changes == release_228.keys, "build 228 changelog and translations differ")
assert(entry_228.changes[0...-1] == entry_227.changes, "build 228 changed the copied changelog")
assert(entry_228.changes.length == entry_227.changes.length + 1 && entry_228.changes.last.include?("text encoding"),
  "build 228 must add only the encoding correction")
release_228.each { |source, translation| assert(catalog[source] == translation, "uncompiled build 228 translation: #{source}") }
assert(GameRoomChangelog.pending_entries(227, 228).map(&:build) == [228], "build 228 repeats already-read build headings")
current_lines = GameRoomChangelog.list_items(GameRoomChangelog.pending_entries(227, 228))
assert(current_lines.first == "Version 2.0, build 228" && current_lines.length == entry_228.changes.length + 1,
  "build 228 must have one version heading")
document = File.read(File.expand_path("../docs/CHANGELOG_2_0.md", __dir__), encoding: "UTF-8")
assert(document.start_with?("# Game Room 2.0 — build 228"), "release document has a stale build heading")
polish, english = document.split("## English", 2)
assert(polish.lines.grep(/^- /).map { |line| line.delete_prefix("- ").strip } == release_228.values,
  "Polish release document differs from the in-game changelog")
assert(english.lines.grep(/^- /).map { |line| line.delete_prefix("- ").strip } == entry_228.changes,
  "English release document differs from the in-game changelog")

entry_229 = entries.find { |entry| entry.build == 229 }
release_229 = JSON.parse(File.read(File.expand_path("../locale/changelog-build-229-pl.json", __dir__), encoding: "UTF-8"))
assert(entry_229.version == "2.0.1" && entry_229.changes == release_229.keys, "2.0.1 changelog and translations differ")
assert(entry_229.changes.length == 29 && entry_229.changes.uniq.length == 29,
  "2.0.1 must preserve twenty-eight notes and append only Krowa")
assert(entry_229.changes[27].include?("Ctrl+F1"), "2.0.1 lacks the empty shortcut-list correction")
assert(entry_229.changes.last.include?("Krowa by paulinux"), "Krowa or its requested author credit missing")
assert(entry_229.changes[24].include?("random or manual") && entry_229.changes[25].include?("rocket-launch") &&
  entry_229.changes[26].include?("opening instructions"), "2.0.1 lacks the latest agreed improvements")
assert(entry_229.changes[22].include?("Battleship") && entry_229.changes[23].include?("Mancala"),
  "new board games missing from release notes")
assert(entry_229.changes[11].include?("Private table checkbox") &&
  entry_229.changes[12].include?("New games are selected in the widget") &&
  entry_229.changes[13].include?("Domino and Mexican Train"), "2.0.1 lost its earlier corrections")
%w[contacts Turn-time token Poker Ctrl+R Keyboard Reshuffling Score].each_with_index do |topic, index|
  assert(entry_229.changes[14 + index].include?(topic), "2.0.1 is missing #{topic}")
end
release_229.each { |source, translation| assert(catalog[source] == translation, "uncompiled 2.0.1 translation: #{source}") }
assert(GameRoomChangelog.pending_entries(228, 229).map(&:build) == [229], "2.0.1 repeats already-read updates")
assert(GameRoomChangelog.pending_entries(nil, 229).map(&:build) == [229], "first 2.0.1 launch repeats past updates")
assert(GameRoomChangelog.pending_entries(229, 229).empty?, "2.0.1 keeps reopening after being read")
assert(GameRoomChangelog.list_items([entry_229]).first == "Version 2.0.1, build 229", "2.0.1 heading differs")
document_229 = File.read(File.expand_path("../docs/CHANGELOG_2_0_1.md", __dir__), encoding: "UTF-8")
assert(document_229.start_with?("# Game Room 2.0.1 — build 229"), "2.0.1 document heading differs")
polish_229, english_229 = document_229.split("## English", 2)
assert(polish_229.lines.grep(/^- /).map { |line| line.delete_prefix("- ").strip } == release_229.values, "2.0.1 Polish document differs")
assert(english_229.lines.grep(/^- /).map { |line| line.delete_prefix("- ").strip } == entry_229.changes, "2.0.1 English document differs")

entry_230 = entries.find { |entry| entry.build == 230 }
release_230 = JSON.parse(File.read(File.expand_path("../locale/changelog-build-230-pl.json", __dir__), encoding: "UTF-8"))
assert(entry_230.version == "2.0.1.1" && entry_230.changes == release_230.keys, "2.0.1.1 changelog and translations differ")
assert(entry_230.changes.length == 9 && entry_230.changes.uniq.length == 9, "2.0.1.1 has duplicate/missing notes")
release_230.each { |source, translation| assert(catalog[source] == translation, "uncompiled 2.0.1.1 translation: #{source}") }
assert(GameRoomChangelog.pending_entries(229, 230).map(&:build) == [230], "2.0.1.1 repeats the previous release")
assert(GameRoomChangelog.pending_entries(nil, 230).map(&:build) == [230], "first 2.0.1.1 launch repeats history")
assert(GameRoomChangelog.pending_entries(230, 230).empty?, "2.0.1.1 reopens after being read")
assert(GameRoomChangelog.list_items([entry_230]).first == "Version 2.0.1.1, build 230", "2.0.1.1 heading differs")
document_230 = File.read(File.expand_path("../docs/CHANGELOG_2_0_1_1.md", __dir__), encoding: "UTF-8")
assert(document_230.start_with?("# Game Room 2.0.1.1 — build 230"), "2.0.1.1 document heading differs")
polish_230, english_230 = document_230.split("## English", 2)
assert(polish_230.lines.grep(/^- /).map { |line| line.delete_prefix("- ").strip } == release_230.values, "2.0.1.1 Polish document differs")
assert(english_230.lines.grep(/^- /).map { |line| line.delete_prefix("- ").strip } == entry_230.changes, "2.0.1.1 English document differs")

entry_231 = entries.find { |entry| entry.build == 231 }
release_231 = JSON.parse(File.read(File.expand_path("../locale/changelog-build-231-pl.json", __dir__), encoding: "UTF-8"))
assert(entry_231.version == "2.0.2" && entry_231.changes == release_231.keys, "2.0.2 changelog and translations differ")
assert(entry_231.changes.length == 10 && entry_231.changes.uniq.length == 10, "2.0.2 has duplicate/missing notes")
assert(entry_231.changes.last.include?("selected for lobby messages") && entry_231.changes.last.include?("does not enable main-screen notifications"), "lobby defaults scope is missing")
assert(entry_231.changes.take(2).last.start_with?("Added Axel Pong"), "Pong must be introduced as new since build 230")
assert(entry_231.changes.none? { |text| text.match?(/Fixed slowdowns|Fixed an error|Restored the original|brought closer|no longer serve/) }, "unreleased Pong test fixes do not belong in public release notes")
assert(entry_231.changes.first.include?("Dragon-Pong") && entry_231.changes.first.include?("Axel and balteam") && entry_231.changes.first.include?("with their permission"), "Pong attribution must lead the changelog")
assert(entry_231.changes.any? { |text| text.include?("Ctrl+1 through Ctrl+0") && text.include?("Settings > Widget.") && text.include?("Table shortcuts list") && text.include?("saved immediately") && text.include?("Cancel in Settings does not undo") }, "inline widget setup and immediate-save instructions missing")
release_231.each { |source, translation| assert(catalog[source] == translation, "uncompiled 2.0.2 translation: #{source}") }
assert(GameRoomChangelog.pending_entries(230, 231).map(&:build) == [231], "2.0.2 repeats the previous release")
assert(GameRoomChangelog.pending_entries(nil, 231).map(&:build) == [231], "first 2.0.2 launch repeats history")
assert(GameRoomChangelog.pending_entries(231, 231).empty?, "2.0.2 reopens after being read")
assert(GameRoomChangelog.list_items([entry_231]).first == "Version 2.0.2, build 231", "2.0.2 heading differs")

document_231 = File.read(File.expand_path("../docs/CHANGELOG_2_0_2.md", __dir__), encoding: "UTF-8")
assert(document_231.start_with?("# Game Room 2.0.2 — build 231"), "2.0.2 document heading differs")
polish_231, english_231 = document_231.split("## English", 2)
assert(polish_231.lines.grep(/^- /).map { |line| line.delete_prefix("- ").strip } == release_231.values, "2.0.2 Polish document differs")
assert(english_231.lines.grep(/^- /).map { |line| line.delete_prefix("- ").strip } == entry_231.changes, "2.0.2 English document differs")

entry_233 = entries.find { |entry| entry.build == 233 }
release_233 = JSON.parse(File.read(File.expand_path('../locale/changelog-build-233-pl.json', __dir__), encoding: 'UTF-8'))
assert(entry_233.version == '2.0.2.2' && entry_233.changes == release_233.keys, 'build 233 notes and translations differ')
assert(entry_233.changes.length == 10 && entry_233.changes.uniq.length == 10, 'build 233 must preserve four notes and append the new game and five improvements')
assert(entry_233.changes[4].include?('Cat, head, tail by TD Programs'), 'new game author is missing')
assert(entry_233.changes.any? { |line| line.include?('Ctrl+F4') && line.include?('ELTEN server') }, 'server ping scope is missing')
assert(entry_233.changes.any? { |line| line.include?('30 table presets') && line.include?('Settings > Widget') && line.include?('saved immediately') }, 'macro setup instructions are missing')
release_233.each { |source, translation| assert(catalog[source] == translation, "uncompiled build 233 translation: #{source}") }
assert(GameRoomChangelog.pending_entries(232, 233).map(&:build) == [233], 'build 233 repeats already-read notes')
assert(GameRoomChangelog.pending_entries(nil, 233).map(&:build) == [233], 'first build 233 launch repeats older notes')
assert(GameRoomChangelog.pending_entries(233, 233).empty?, 'build 233 changelog reopens after being read')
assert(GameRoomChangelog.list_items([entry_233]).first == 'Version 2.0.2.2, build 233', 'build 233 heading differs')

entry_234 = entries.find { |entry| entry.build == 234 }
release_234 = JSON.parse(File.read(File.expand_path('../locale/changelog-build-234-pl.json', __dir__), encoding: 'UTF-8'))
assert(entry_234.version == '2.0.2.3' && entry_234.changes == release_234.keys, 'build 234 notes and translations differ')
assert(entry_234.changes.length == 3 && entry_234.changes.uniq.length == 3, 'build 234 has missing or duplicate notes')
release_234.each { |source, translation| assert(catalog[source] == translation, "uncompiled build 234 translation: #{source}") }
assert(GameRoomChangelog.pending_entries(233, 234).map(&:build) == [234], 'build 234 repeats already-read notes')
assert(GameRoomChangelog.pending_entries(nil, 234).map(&:build) == [234], 'first build 234 launch repeats older notes')
assert(GameRoomChangelog.pending_entries(234, 234).empty?, 'build 234 changelog reopens after being read')
assert(GameRoomChangelog.list_items([entry_234]).first == 'Version 2.0.2.3, build 234', 'build 234 heading differs')
assert(entry_234.changes.last.include?('HTTP') && entry_234.changes.last.include?('Communications'), 'ping transport is ambiguous')

entry_235 = entries.find { |entry| entry.build == 235 }
release_235 = JSON.parse(File.read(File.expand_path('../locale/changelog-build-235-pl.json', __dir__), encoding: 'UTF-8'))
assert(entry_235.version == '2.0.2.4' && entry_235.changes == release_235.keys, 'build 235 notes and translations differ')
assert(entry_235.changes.length == 1 && entry_235.changes.first.include?('Doubles'), 'build 235 should describe only the doubles correction')
release_235.each { |source, translation| assert(catalog[source] == translation, "uncompiled build 235 translation: #{source}") }
assert(GameRoomChangelog.pending_entries(234, 235).map(&:build) == [235], 'build 235 repeats already-read notes')
assert(GameRoomChangelog.pending_entries(nil, 235).map(&:build) == [235], 'first build 235 launch repeats older notes')
assert(GameRoomChangelog.pending_entries(235, 235).empty?, 'build 235 changelog reopens after being read')
assert(GameRoomChangelog.list_items([entry_235]).first == 'Version 2.0.2.4, build 235', 'build 235 heading differs')
document_235 = File.read(File.expand_path('../docs/CHANGELOG_2_0_2_4.md', __dir__), encoding: 'UTF-8')
polish_235, english_235 = document_235.split('## English', 2)
assert(polish_235.lines.grep(/^- /).map { |line| line.delete_prefix('- ').strip } == release_235.values, 'build 235 Polish document differs')
assert(english_235.lines.grep(/^- /).map { |line| line.delete_prefix('- ').strip } == entry_235.changes, 'build 235 English document differs')

entry_236 = entries.find { |entry| entry.build == 236 }
release_236 = JSON.parse(File.read(File.expand_path('../locale/changelog-build-236-pl.json', __dir__), encoding: 'UTF-8'))
assert(entry_236.version == '2.0.2.5' && entry_236.changes == release_236.keys, 'build 236 notes and translations differ')
assert(entry_236.changes.length == 3 && entry_236.changes.uniq.length == 3, 'build 236 has missing or duplicate notes')
release_236.each { |source, translation| assert(catalog[source] == translation, "uncompiled build 236 translation: #{source}") }
assert(GameRoomChangelog.pending_entries(235, 236).map(&:build) == [236], 'build 236 repeats already-read notes')
assert(GameRoomChangelog.pending_entries(nil, 236).map(&:build) == [236], 'first build 236 launch repeats older notes')
assert(GameRoomChangelog.pending_entries(236, 236).empty?, 'build 236 changelog reopens after being read')
assert(GameRoomChangelog.list_items([entry_236]).first == 'Version 2.0.2.5, build 236', 'build 236 heading differs')
assert(entry_236.changes[1].include?('All participants'), 'mixed-match update requirement missing')
assert(entry_236.changes.last.include?('three-second delay at the start'), 'initial countdown change missing')
document_236 = File.read(File.expand_path('../docs/CHANGELOG_2_0_2_5.md', __dir__), encoding: 'UTF-8')
assert(document_236.start_with?('# Game Room 2.0.2.5 — build 236'), 'build 236 document heading differs')
polish_236, english_236 = document_236.split('## English', 2)
assert(polish_236.lines.grep(/^- /).map { |line| line.delete_prefix('- ').strip } == release_236.values, 'build 236 Polish document differs')
assert(english_236.lines.grep(/^- /).map { |line| line.delete_prefix('- ').strip } == entry_236.changes, 'build 236 English document differs')

entry_237 = entries.find { |entry| entry.build == 237 }
release_237 = JSON.parse(File.read(File.expand_path('../locale/changelog-build-237-pl.json', __dir__), encoding: 'UTF-8'))
assert(entry_237.version == '2.0.3' && entry_237.changes == release_237.keys, 'build 237 notes and translations differ')
assert(entry_237.changes.length == 14 && entry_237.changes.uniq.length == 14, 'build 237 has missing or duplicate notes')
assert(entry_237.changes.first.include?('budyn1211, known on ELTEN as balteam'), 'Audio Ball author alias missing')
assert(release_237.values.first.include?('budyn1211, znanego na ELTEN-ie jako balteam'), 'Polish Audio Ball author alias missing')
assert(entry_237.changes[4].include?('F1') && entry_237.changes[4].include?('Ctrl+F1'), 'background help note missing')
assert(entry_237.changes[5].include?('serve in Axel Pong after using chat'), 'Pong chat correction missing')
assert(entry_237.changes[6].include?('installation error') && entry_237.changes[6].include?('Unicode'), 'Unicode installation correction missing')
assert(entry_237.changes[7].include?('Ctrl+J') && entry_237.changes[7].include?('widget') && entry_237.changes[7].include?('notification'), 'widget invitation shortcut note missing')
assert(entry_237.changes[8].include?('Settings > Language') && entry_237.changes[9].include?('balteam'), 'language choice or translator credit missing')
assert(entry_237.changes[10].include?('watching Axel Pong') && entry_237.changes[11].include?('Accept'), 'observer/teams notes missing')
assert(entry_237.changes[12].include?('observer role') && entry_237.changes[13].include?('reading position'), 'roles/focus notes missing')
assert(entry_237.changes.drop(1).none? { |line| line.include?('Audio Ball') }, 'unreleased Audio Ball details added to release notes')
release_237.each { |source, translation| assert(catalog[source] == translation, "uncompiled build 237 translation: #{source}") }
assert(GameRoomChangelog.pending_entries(236, 237).map(&:build) == [237], 'build 237 repeats already-read notes')
assert(GameRoomChangelog.pending_entries(237, 237).empty?, 'build 237 changelog reopens after being read')
assert(GameRoomChangelog.list_items([entry_237]).first == 'Version 2.0.3, build 237', 'build 237 heading differs')

entry_238 = entries.find { |entry| entry.build == 238 }
assert(entry_238.version == '2.0.3.1' && entry_238.changes.length == 8 && entry_238.changes.uniq.length == 8,
  'build 238 must contain seven approved changes and the arcade exception')
assert(entry_238.changes.all? { |text| !catalog[text].to_s.empty? }, 'build 238 has an untranslated change')
assert(GameRoomChangelog.pending_entries(237, 238).map(&:build) == [238], 'build 238 repeats older changes')
assert(GameRoomChangelog.pending_entries(nil, 238).map(&:build) == [238], 'first build 238 launch repeats history')
assert(GameRoomChangelog.pending_entries(238, 238).empty?, 'build 238 reopens after being read')
assert(GameRoomChangelog.list_items([entry_238]).first == 'Version 2.0.3.1, build 238', 'build 238 heading differs')
document_238 = File.read(File.expand_path('../docs/CHANGELOG_2_0_3_1.md', __dir__), encoding: 'UTF-8')
assert(document_238.start_with?('# Game Room 2.0.3.1 — build 238'), 'build 238 document heading differs')
polish_238, english_238 = document_238.split('## English', 2)
[polish_238, english_238].zip([entry_238.changes.map { |text| catalog.fetch(text) }, entry_238.changes]).each do |section, expected|
  actual = section.lines.grep(/^- /).map { |line| line.delete_prefix('- ').strip }
  assert(actual == expected.take(7) && section.strip.end_with?(expected.last), 'build 238 approved text or arcade note changed')
end

entry_239 = entries.find { |entry| entry.build == 239 }
assert(entry_239.version == '2.0.4' && entry_239.changes.length == 26 && entry_239.changes.uniq.length == 26,
  'build 239 must contain the approved changes and minimum ELTEN version')
assert(entry_239.changes.any? { |text| text.include?('P2P') && text.include?('off by default') && text.include?('defaulting to 8') && text.include?('relay server') }, 'optional P2P settings or relay fallback missing')
assert(entry_239.changes.any? { |text| text.include?('Ctrl+F4') && text.include?('HTTP') && text.include?('Communications') && text.include?('P2P') && text.include?('Mixed') }, 'ping transport distinctions missing')
assert(entry_239.changes.grep(/Ctrl\+J/).size == 1 && entry_239.changes.any? { |text| text.include?('Ctrl+J') && text.include?('context menu') && text.include?('typing in chat') && text.include?('settings') }, 'global invitation shortcut scope missing or duplicated')
assert(entry_239.changes.any? { |text| text.include?('Opening Game Room again') && text.include?("ELTEN's Windows menu") }, 'single-instance window cleanup note missing')
assert(entry_239.changes.any? { |text| text.include?('Fixed opening Messages') && text.include?('widget') && text.include?('receiving updates') }, 'widget navigation and game updates note missing')
assert(entry_239.changes.any? { |text| text.include?('Corrected many quiz questions') && text.include?('questions and answers') }, 'broader quiz wording corrections missing')
assert(entry_239.changes[1].include?('War and Scientific War by balteam'), 'new games or author credit missing')
assert(entry_239.changes.grep(/Ctrl\+M/).size == 1, 'Added the excluded Ctrl+M focus change to the changelog')
assert(entry_239.changes.first == 'This version requires ELTEN 3.0.4 or later.', 'minimum ELTEN version missing')
assert(entry_239.changes.all? { |text| !catalog[text].to_s.empty? }, 'build 239 has an untranslated change')
assert(GameRoomChangelog.pending_entries(238, 239).map(&:build) == [239], 'build 239 repeats older changes')
assert(GameRoomChangelog.pending_entries(nil, 239).map(&:build) == [239], 'first build 239 launch repeats history')
assert(GameRoomChangelog.pending_entries(239, 239).empty?, 'build 239 reopens after being read')
assert(GameRoomChangelog.list_items([entry_239]).first == 'Version 2.0.4, build 239', 'build 239 heading differs')
document_239 = File.read(File.expand_path('../docs/CHANGELOG_2_0_4.md', __dir__), encoding: 'UTF-8')
assert(document_239.start_with?('# Game Room 2.0.4 — build 239'), 'build 239 document heading differs')
polish_239, english_239 = document_239.split('## English', 2)
[polish_239, english_239].zip([entry_239.changes.map { |text| catalog.fetch(text) }, entry_239.changes]).each do |section, expected|
  actual = section.lines.grep(/^- /).map { |line| line.delete_prefix('- ').strip }
  assert(actual == expected, 'build 239 approved text differs between the document and runtime')
end

puts "Changelog tests passed: first launch, updates, downgrade, Enter, storage, old notes preserved and bilingual build 239 notes"
