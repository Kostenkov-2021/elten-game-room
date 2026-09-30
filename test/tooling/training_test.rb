require_relative '../../lib/game_bots'
raise 'training strategy leaked into runtime' if GameRoomBots.const_defined?(:LearnedStrategy, false)

def _(text)
  text
end

require_relative "../../tools/training/game_training"
require_relative "../../games/tic_tac_toe"

def assert(condition, message)
  raise message if !condition
end

policy = GameRoomTraining::PolicyTable.new
policy.update("state", "left", 1.0)
policy.update("state", "left", 0.0)
policy.update("state", "right", -1.0)
assert(policy.visits("state", "left") == 2, "policy visits were not counted")
assert(policy.value("state", "left") == 0.5, "policy average was calculated incorrectly")
assert(policy.best_action("state", ["left", "right"]) == "left", "policy selected the weaker action")
restored = GameRoomTraining::PolicyTable.from_json(policy.to_json)
assert(restored.value("state", "left") == 0.5, "serialized policy changed its values")

game = GameRoomGames::TicTacToe.new
first_players = GameRoomParticipants.bots_for(1, 2)
second_players = GameRoomParticipants.bots_for(99, 2)
first_empty = GameRoomSimulation::Environment.new_game(game: game, players: first_players, seed: 1)
second_empty = GameRoomSimulation::Environment.new_game(game: game, players: second_players, seed: 1)
assert(
  game.bot_state_key(first_empty.replay, first_players.first) == game.bot_state_key(second_empty.replay, second_players.first),
  "learned states depend on a table-specific computer id"
)
trainer = GameRoomTraining::SelfPlayTrainer.new(
  game: game,
  policy: GameRoomTraining::PolicyTable.new,
  epsilon: 0.25
)
report = trainer.train(episodes: 12, seed: 500)
assert(report.episodes == 12, "self-play skipped episodes")
assert(report.unfinished == 0, "a self-play episode did not finish")
assert(trainer.policy.state_count > 0, "self-play did not learn any states")
assert(trainer.policy.decision_count > 0, "self-play did not learn any decisions")

tournament = GameRoomTraining::Tournament.new(
  game: game,
  competitors: {
    "random" => GameRoomBots::RandomStrategy.new,
    "heuristic" => GameRoomBots::HeuristicStrategy.new
  }
)
tournament_report = tournament.run(seeds: [10, 11, 12])
assert(tournament_report.matches == 6, "the tournament did not swap seats for every seed")
assert(tournament_report.ratings.keys.sort == ["heuristic", "random"], "the tournament did not rate both strategies")
assert(tournament_report.results.all? { |entry| entry[:result].finished? }, "a tournament match did not finish")

puts "Bot training and tournament tests passed"

# Six-episode extraction regression on a separate seed and fresh policy.
policy = GameRoomTraining::PolicyTable.new
trainer = GameRoomTraining::SelfPlayTrainer.new(game: GameRoomGames::TicTacToe.new, policy: policy)
report = trainer.train(episodes: 6, seed: 38)
raise "training did not finish after extraction" unless report.episodes == 6 && report.unfinished == 0
raise "training did not update policy" unless policy.state_count > 0 && policy.decision_count > 0
puts "PASS LearnedStrategy loads only from training and completes six deterministic self-play episodes"
