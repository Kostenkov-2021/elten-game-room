require_relative "../support/translation_reference"
require_relative "../support/binary_rule_dictionary"
$rules_english = true
GameRoomTestLocalization.use_language(:en)
require_relative '../support/score_announcements'
require_relative '../support/card_reshuffle'

# Shared fixture definitions use English; restore the host-compatible dictionary
# for the language checks. Missing translations must keep binary source bytes.
def _(source)
  return source if $rules_english
  $rules_dictionary.send(:_, source)
end

[false, true].each do |english|
  $rules_english = english
  GameRoomTestLocalization.use_language(english ? :en : :pl)
  [GameRoomGames::Uno, GameRoomGames::Makao, GameRoomGames::NinetyNine,
    GameRoomGames::Rummy, GameRoomGames::Poker].each do |type|
    game, repo, session, state, selection = reshuffle_fixture(type, "Alice")
    replay = append_action(game, session, repo, [], game.replay(session, [], repo), "Alice", selection, context_for)
    text = replay.history.find { |entry| entry.kind == :reshuffle }.text
    expected = english ? "The deck was reshuffled." : "Przetasowano talię."
    assert(text == expected && text.encoding == Encoding::UTF_8 && text.valid_encoding?, "#{game.id}: reshuffle translation/encoding")
    assert((text + " Zażółć").valid_encoding?, "#{game.id}: reshuffle incompatible with host language")
  end

  [GameRoomGames::Uno, GameRoomGames::Farkle, GameRoomGames::Tysiac, GameRoomGames::Spades,
    GameRoomGames::Categories, GameRoomGames::QuizParty, GameRoomGames::Scrabble, GameRoomGames::Rummy,
    GameRoomGames::Domino, GameRoomGames::MexicanTrain, GameRoomGames::Yahtzee, GameRoomGames::NinetyNine,
    GameRoomGames::Monopoly, GameRoomGames::Poker, GameRoomGames::Taboo].each do |type|
    game, replay = score_replay(type)
    text = s_message(game, replay)
    assert(text.valid_encoding? && (text.encoding == Encoding::UTF_8 || text.ascii_only?), "#{game.id}: score shortcut encoding")
    assert((text + " Zażółć").valid_encoding?, "#{game.id}: score incompatible with host language")
  end
  game, replay = score_replay(GameRoomGames::Taboo)
  replay.state[:scores].replace([3, 8])
  assert(s_message(game, replay) == (english ? "Team 2: 8; Team 1: 3" : "Drużyna 2: 8; Drużyna 1: 3"), "Taboo score translation")

  entry = GameRoomChangelog::ENTRIES.find { |item| item.build == 229 }
  translations = GameRoomTest::TranslationReference.fetch("changelog_229")
  lines = GameRoomChangelog.list_items([entry], translator: GameRoomLocalization.method(:translate))
  assert(lines.drop(1) == (english ? entry.changes : translations.values), "new changelog not translated by Game Room catalog")
  assert(lines.length == entry.changes.length + 1 && lines.all? { |line| line.valid_encoding? && (line.encoding == Encoding::UTF_8 || line.ascii_only?) }, "changelog heading/encoding")
end
puts "PASS binary card announcements: native-compatible PL/EN dictionary, reshuffle, score shortcuts, one bilingual changelog heading"
