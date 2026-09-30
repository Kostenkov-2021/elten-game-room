require_relative '../support/new_games_fixture'

monopoly = GameRoomGames::Monopoly.new
yahtzee = GameRoomGames::Yahtzee.new
uno = GameRoomGames::Uno.new
poker = GameRoomGames::Poker.new
makao = GameRoomGames::Makao.new

[monopoly, yahtzee, uno, poker, makao].each do |game|
  assert(game.minimum_players >= 2 && game.maximum_players <= 8, "#{game.id} has an unsupported player range")
  assert(game.rule_book.sections.any?, "#{game.id} has no rules")
  assert(game.validation_error(game.default_options, player_count: 3) == nil, "#{game.id} rejects its defaults")
end

puts "Card and dice player-count, rulebook and default-option contracts passed"
