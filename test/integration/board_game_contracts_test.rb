require_relative '../support/new_board_games'

reversi = GameRoomGames::Reversi.new
checkers = GameRoomGames::Checkers.new
chess = GameRoomGames::Chess.new
ludo = GameRoomGames::Ludo.new

[reversi, checkers, chess, ludo].each do |game|
  assert(!game.rule_book.sections.empty?, "#{game.id} has no rules")
  assert(game.bot_strategy != nil, "#{game.id} has no bot strategy")
end

# Every new bot must be able to choose and submit a legal production action.
[reversi, checkers, chess, ludo].each do |game|
  count = [game.minimum_players, 2].max
  bot_players = (1..count).map { |index| "Computer #{index}" }
  environment = GameRoomSimulation::Environment.new_game(game: game, players: bot_players, seed: 165)
  actor = environment.active_actor
  actions = environment.legal_actions(actor)
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  choice = GameRoomBots.choose(game.bot_strategy, {
    actions: actions,
    observation: environment.observation(actor),
    actor: actor,
    random_source: environment.random_source,
    game: game,
    replay: environment.replay,
    context: environment.context,
    simulation: environment
  })
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
  assert(choice != nil, "#{game.id} bot did not choose a move")
  assert(environment.step(choice, actor: actor) == :ok, "#{game.id} bot produced an illegal move")
  stats = game.bot_strategy.respond_to?(:last_stats) ? game.bot_strategy.last_stats : {}
  puts "#{game.id} first bot decision: #{format('%.3f', elapsed)} seconds; #{stats.inspect}"
end

puts "Board game rulebook and legal bot action contracts passed"
