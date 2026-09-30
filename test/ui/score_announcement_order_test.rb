if ARGV.delete("--binary")
  require_relative "../support/binary_rules_load"
  BinaryRulesLoad.load(File.expand_path(__FILE__))
  exit
end
require_relative '../support/score_announcements'

players = %w[Alice Bob Carol Dave]
base = GameRoomGames::Base.new
scores = { "Alice" => 0, "Bob" => -15, "Carol" => 10, "Dave" => 10 }
assert(base.score_announcement_order(players, scores) == %w[Carol Dave Alice Bob], "zero, negative scores or stable ties")
assert(base.score_announcement_order(players, scores, eliminated: { "Carol" => true }) == %w[Dave Alice Bob Carol], "eliminated last")
assert(players == %w[Alice Bob Carol Dave] && scores["Carol"] == 10, "helper changed seats/scores")

types = [GameRoomGames::Uno, GameRoomGames::Farkle, GameRoomGames::Tysiac,
  GameRoomGames::Spades, GameRoomGames::Categories, GameRoomGames::QuizParty,
  GameRoomGames::Scrabble, GameRoomGames::Rummy, GameRoomGames::Domino, GameRoomGames::MexicanTrain]
types.each do |type|
  game, replay = score_replay(type)
  replay.state[:scores].replace(scores)
  assert_names(s_message(game, replay), %w[Carol Dave Alice Bob], game.id)
  helper = game.respond_to?(:scores_text, true) ? :scores_text : :score_text
  if game.respond_to?(helper, true)
    assert_names(game.send(helper, replay.state), players, "#{game.id}: round summary order")
  end
  if replay.state[:eliminated]
    replay.state[:eliminated]["Carol"] = true
    text = s_message(game, replay)
    assert_names(text, %w[Dave Alice Bob Carol], "#{game.id}: elimination")
    assert(text.match?(/Carol\D+10/), "#{game.id}: eliminated score was erased")
  end
end

game, replay = score_replay(GameRoomGames::Uno)
replay.state[:scores].replace(scores)
replay.state[:round_eliminated]["Carol"] = true
assert_names(s_message(game, replay), %w[Carol Dave Alice Bob], "UNO: No Mercy round elimination is not match elimination")

game, replay = score_replay(GameRoomGames::NinetyNine)
replay.state[:tokens].replace({ "Alice" => 0, "Bob" => 1, "Carol" => 3, "Dave" => 2 })
assert_names(s_message(game, replay), %w[Carol Dave Bob Alice], "99: zero tokens still in game")
replay.state[:eliminated]["Carol"] = true
assert_names(s_message(game, replay), %w[Dave Bob Alice Carol], "99: eliminated last")
assert_names(game.send(:tokens_text, replay.state), players, "99: history still seat order")

game, replay = score_replay(GameRoomGames::Yahtzee)
replay.state[:totals].replace(scores)
replay.state[:sheets]["Bob"]["chance"] = 40
assert_names(s_message(game, replay), %w[Bob Carol Dave Alice], "Yahtzee includes current sheet")
assert_names(game.send(:scores_text, replay.state), players, "Yahtzee: history order")

[GameRoomGames::Spades, GameRoomGames::Domino].each do |type|
  game = type.new
  options = game.default_options.merge(game.id == "spades" ? { "team_size" => 2 } : { "teams" => true, "team_count" => "2" })
  options = game.with_team_assignment(options, players: players, seats: [0, 1, 0, 1])
  replay = game.replay({ "options" => JSON.generate(options) }, [], NewGames116Repository.new(players))
  first, second = replay.state[:scores].keys
  replay.state[:scores][first], replay.state[:scores][second] = 0, 30
  assert_names(s_message(game, replay), %w[Bob Dave Alice Carol], "#{game.id}: team scores")
  if replay.state[:eliminated]
    replay.state[:eliminated][second] = true
    assert_names(s_message(game, replay), %w[Alice Carol Bob Dave], "#{game.id}: eliminated team")
  end
end

game, replay = score_replay(GameRoomGames::Taboo)
replay.state[:scores].replace([-5, 12])
assert(s_message(game, replay) == "Team 2: 12; Team 1: -5", "Taboo team score order")
replay.state[:scores].replace([7, 7])
assert(s_message(game, replay) == "Team 1: 7; Team 2: 7", "Taboo tied teams")

game, replay = score_replay(GameRoomGames::Biblios)
assert(!game.game_shortcuts(replay, "Alice").any? { |s| s.key == "s" }, "Biblios hidden final scores exposed")
replay.state[:hands].replace({ "Alice" => ["pA"], "Bob" => [], "Carol" => ["mA", "fA"], "Dave" => ["hA"] })
replay.state[:phase], replay.state[:winner], replay.winner = :finished, "Carol", "Carol"
assert_names(s_message(game, replay), %w[Carol Alice Dave Bob], "Biblios final victory points")

game, replay = score_replay(GameRoomGames::Monopoly)
replay.state[:cash].replace({ "Alice" => 0, "Bob" => 100, "Carol" => 1000, "Dave" => 20 })
property = replay.state[:board].find { |square| square[:type] == :property && square[:price] > 100 }
replay.state[:owners][property[:index]] = "Alice"
replay.state[:bankrupt]["Carol"] = true
assert_names(s_message(game, replay), %w[Alice Bob Dave Carol], "Monopoly sorts net worth, not cash; bankrupt last")

%w[holdem draw].each do |variant|
  game, replay = score_replay(GameRoomGames::Poker, "variant" => variant)
  replay.state[:stacks].replace({ "Alice" => 50, "Bob" => 10, "Carol" => 100, "Dave" => 0 })
  replay.state[:phase] = :betting
  replay.state[:hands]["Dave"] = %w[AS KS]
  own = s_message(game, replay)
  assert(!own.match?(/Bob|Carol|Dave/) && own.include?("50"), "Poker S no longer own stack")
  assert_names(s_message(game, replay, shift: true), %w[Carol Bob Dave], "Poker #{variant} other stacks")
  assert(!game.eliminated_from_game?(replay, "Dave"), "all-in incorrectly eliminated")
end

puts "PASS score announcements: 16 games, negative/zero/tied scores, teams, permanent elimination, hidden information and unchanged state/history"
