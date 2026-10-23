require_relative '../../lib/game_bots'

def _(text)
  text
end

require_relative '../../tools/training/game_training'
require_relative '../../games/tic_tac_toe'

game = GameRoomGames::TicTacToe.new
competitors = {
  'first' => GameRoomBots::HeuristicStrategy.new,
  'second' => GameRoomBots::HeuristicStrategy.new
}
unfinished = GameRoomTraining::Tournament.new(
  game: game, competitors: competitors, max_actions: 1
).run(seeds: [1, 2])

raise 'fixture did not reach the real action limit' unless unfinished.results.all? do |entry|
  result = entry.fetch(:result)
  !result.finished? && !result.draw && result.reason == :action_limit && result.actions == 1
end
raise 'unfinished attempts counted as draws' unless unfinished.draws.zero?
raise 'unfinished attempts were not reported separately' unless unfinished.unfinished == 4
raise 'attempted matches disappeared' unless unfinished.matches == 4 && unfinished.results.size == 4
raise 'unfinished attempts awarded a win or changed Elo' unless unfinished.wins.empty? && unfinished.ratings.empty?

completed = GameRoomTraining::Tournament.new(
  game: game, competitors: competitors
).run(seeds: [1, 2])
raise 'complete-match fixture did not finish' unless completed.results.all? { |entry| entry.fetch(:result).finished? }
raise 'complete attempts marked unfinished' unless completed.unfinished.zero?
raise 'complete outcomes lost' unless completed.draws + completed.wins.values.sum == completed.matches
raise 'complete games stopped updating Elo' unless completed.ratings.keys.sort == competitors.keys.sort

puts 'PASS offline training separates action-limit attempts from completed draws and Elo results'
