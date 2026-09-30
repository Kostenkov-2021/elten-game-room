require_relative "ui"
require_relative "../../lib/game_surfaces"
require_relative "new_games_fixture"
require_relative "../../games/ninety_nine"
require_relative "../../games/rummy"
require_relative "../../games/domino"
require_relative "../../games/mexican_train"
require_relative "../../games/scrabble"
require_relative "../../games/taboo"
require_relative "../../games/farkle"
require_relative "../../games/tysiac"
require_relative "../../games/spades"
require_relative "../../games/categories"
require_relative "../../content/languages"
require_relative "../../content/quiz_pl_wikidata"
require_relative "../../games/quiz_party"

def score_replay(type, options = {})
  game = type.new
  players = %w[Alice Bob Carol Dave]
  repository = NewGames116Repository.new(players)
  session = { "options" => JSON.generate(game.default_options.merge(options)) }
  [game, game.replay(session, [], repository)]
end

def s_message(game, replay, shift: false)
  before = Marshal.dump(replay)
  shortcut = game.game_shortcuts(replay, "Alice").find do |s|
    s.key == "s" && s.modifiers.to_a == (shift ? [:shift] : [])
  end
  assert(shortcut && shortcut.kind == :announcement, "#{game.id}: missing score shortcut")
  assert(Marshal.dump(replay) == before, "#{game.id}: shortcut mutated game state/history")
  shortcut.message
end

def assert_names(text, expected, label)
  actual = text.scan(/Alice|Bob|Carol|Dave/)
  assert(actual == expected, "#{label}: expected #{expected.inspect}, got #{text.inspect}")
end
