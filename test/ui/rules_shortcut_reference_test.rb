require_relative "../support/ui"
require "json"
class Program
  def self.server_app(**_options); end
end
require_relative "../../__app"

def assert(value, message); raise message unless value; end

EltenGameRoom::GAME_REGISTRY.ids.each do |id|
  game = EltenGameRoom::GAME_REGISTRY.build(id)
  doc = game.rule_book.documents.find { |item| item.id == :controls }
  authored = JSON.parse(File.read(File.expand_path("../../tools/data/rulebooks/#{id}.json", __dir__)))
    .fetch("sections").find { |s| s["id"] == "controls" }.fetch("paragraphs")
  assert(doc.paragraphs == authored.map { |p| p["en"] }, "#{id}: unrelated help added")
  %w[en pl].each do |language|
    keys = authored.map do |row|
      text = row.fetch(language)
      key, body = text.split(": ", 2)
      assert(body && !key.match?(/,| and | or | i | lub /), "#{id}: condensed row: #{text}")
      assert(!text.match?(/chat|czat|Ctrl\+F1|F2|F3|Ctrl\+R|Ctrl\+Q/i), "#{id}: room/global shortcut in game help")
      key
    end
    assert(keys.uniq == keys, "#{id}: duplicate shortcut")
  end
end
field = FakeControl.new
field.define_singleton_method(:get_tips) { ["Native game move", "Press Ctrl+F1 to read the game rules."] }
GameRoomContextHelp.exclude_from_game_help([field], ["Press Ctrl+F1 to read the game rules."])
GameRoomContextHelp.replace([field], ["Current game move"], source: :game)
assert(GameRoomContextHelp.field_tips(field).include?("Press Ctrl+F1 to read the game rules."), "F1 lost global rules help")
assert(GameRoomContextHelp.game_field_tips([field]) == ["Current game move", "Native game move"], "live game help leaked Ctrl+F1")
puts "PASS game shortcut references: #{EltenGameRoom::GAME_REGISTRY.ids.length} games, individual key rows in PL/EN, no room/chat/global controls, shared current F1 tips preserved"
