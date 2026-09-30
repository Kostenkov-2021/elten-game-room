require_relative "../../tools/training/match_runner"
require_relative "../support/new_board_games"

def run_random_match(game, players:, seed:, limit:)
  GameRoomSimulation::MatchRunner.new(
    game: game,
    players: players,
    default_strategy: GameRoomBots::RandomStrategy.new,
    max_actions: limit
  ).run(seed: seed)
end

[
  [GameRoomGames::Reversi.new, ["R1", "R2"], 11, 100],
  [GameRoomGames::Checkers.new, ["D1", "D2"], 12, 1_000],
  [GameRoomGames::Chess.new, ["C1", "C2"], 13, 1_000],
  [GameRoomGames::Ludo.new, ["L1", "L2", "L3", "L4"], 14, 5_000]
].each do |game, players, seed, limit|
  result = run_random_match(game, players: players, seed: seed, limit: limit)
  detail = if result.final_state.is_a?(Hash)
    base = "current=#{result.final_state[:current_player].inspect}, forced=#{result.final_state[:forced_from].inspect}, winner=#{result.final_state[:winner].inspect}, draw=#{result.final_state[:draw].inspect}"
    if game.id == "checkers" && result.final_state[:forced_from] != nil
      x, y = result.final_state[:forced_from]
      marker = game.send(:player_index, result.final_state[:players], result.final_state[:current_player])
      raw = game.send(:raw_captures, result.final_state, marker, only: result.final_state[:forced_from])
      base += ", piece=#{result.final_state[:board][y][x].inspect}, raw_captures=#{raw.map(&:event_value).inspect}"
    end
    base
  else
    result.final_state.inspect
  end
  assert(result.finished?, "#{game.id} random match did not reach a valid ending: #{result.reason}; #{detail}")
  assert(result.events.length == result.actions, "#{game.id} accepted a partial random action")
  puts "#{game.id} random match: #{result.actions} actions"
end

puts "New board game complete-match tests passed"
