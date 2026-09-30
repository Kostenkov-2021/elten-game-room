require_relative "../../support/translation_reference"
require_relative "../../support/cat_head_tail_dictionary"
require "digest"

# Verbatim wording supplied in TD Programs PR #12, head 7930486.
# Canonical JSON hashes ignore line endings, not the author's text or punctuation.
expected_sources = {
  "tools/data/rulebooks/cat_head_tail.json" => "e0f59edf05bd62413749e2bd46921aa2b6e0bea5476868ea3083686a9c08c94f"
}
expected_sources.each do |relative, expected|
  content = JSON.parse(File.read(File.join(BinaryRulesLoad::ROOT, relative), encoding: "UTF-8"))
  actual = Digest::SHA256.hexdigest(JSON.generate(content))
  raise "Author text was changed: #{relative}" unless actual == expected
end

original = GameRoomTest::TranslationReference.fetch("cat_head_tail")
raise 'Author message reference was changed' unless Digest::SHA256.hexdigest(JSON.generate(original)) ==
  'ba36af511de7a069383fd0a9439a657a2a40e2ea9cbfaedcb9a3bee151106e70'
game = EltenGameRoom::GAME_REGISTRY.build("cat_head_tail")
repository = Object.new
def repository.players_for(session); session.fetch("__players"); end
def repository.actor_of(event, _session); event.fetch("actor"); end
def repository.event_id(event); event.fetch("id"); end
session = { "options" => JSON.generate(game.default_options), "__players" => ["Żaneta", "Łukasz"] }
events = [
  { "id" => 1, "actor" => "Żaneta", "action" => "roll", "value" => "6" },
  { "id" => 2, "actor" => "Żaneta", "action" => "bank", "value" => "" }
]

[:pl, :en, :missing_translation].each do |language|
  $cht_language = language
  GameRoomTestLocalization.use_language(language)
  original.each do |source, polish|
    expected = language == :pl ? polish : source
    actual = game.send(:_, source.b)
    raise "Author message changed: #{source}" unless actual == expected
    raise "Translation context leaked to speech" if actual.include?("\u0004")
    raise "Invalid author text encoding" unless (actual + " — żółty").valid_encoding?
  end

  replay = game.replay(session, events, repository)
  actual_bank = replay.history.find { |entry| entry.key == "bank:2" }.text
  expected_bank = language == :pl ?
    "Żaneta bankuje 6 pkt, ma teraz 6." :
    "Żaneta banked 6 points and now has 6."
  raise "Bank action no longer speaks the author's wording" unless actual_bank == expected_bank

  # Game-specific translations must not overwrite existing Farkle wording.
  bank_source = "%{player} banked %{points} points and now has %{total}."
  plain_expected = language == :pl ?
    "%{player} zapisuje %{points} punktów i ma teraz %{total}." : bank_source
  raise "Cat's bank text overwrote the shared Farkle translation" unless GameRoomLocalization.translate(bank_source.b) == plain_expected
  farkle = GameRoomGames::Farkle.new
  farkle_state = farkle.send(:initial_state, ["Żaneta", "Łukasz"], farkle.default_options)
  farkle_state.update(phase: :awaiting_roll, current_player: "Żaneta", turn_points: 100)
  farkle_history = []
  raise "Farkle bank fixture was rejected" unless farkle.send(:apply_bank, farkle_state, { "id" => 3 }, "Żaneta", repository, farkle_history)
  expected_farkle = plain_expected % { player: "Żaneta", points: 100, total: 100 }
  raise "Farkle inherited a different game's private dictionary" unless farkle_history.find { |entry| entry.kind == :bank }.text == expected_farkle
end
puts "PASS exact author rulebook and all ten PL/EN messages, scoped bank/Roll translations, unchanged Farkle, native binary lookup and English fallback"
