require_relative "../support/cases"
require_relative "../../lib/game_snapshot"
require_relative "../../games/tic_tac_toe"
require_relative "../../lib/game_simulation"
include GameRoomTest::Assertions

cases = GameRoomTest::Cases.new
cases.run('snapshot isolates a real nil-state board replay') do
  env = GameRoomSimulation::Environment.new_game(game: GameRoomGames::TicTacToe.new, players: %w[Alice Bob])
  original = env.replay
  copy = GameRoomSnapshot.copy(original)
  assert(original.state.nil? && copy.state.nil?, 'optional state normalized into another type')
  copy.board[0][0] = 1
  copy.players[0].replace('Someone else')
  assert(original.board[0][0].nil? && original.players.first == 'Alice', 'snapshot shared mutable board or identity')
end
cases.run('snapshot preserves internal aliases and cycles without sharing its source') do
  shared = ['value']
  original = [shared, shared]
  original << original
  copy = GameRoomSnapshot.copy(original)
  assert(copy[0].equal?(copy[1]) && copy[2].equal?(copy), 'internal graph changed')
  assert(!copy[0].equal?(shared), 'graph was shallow copied')
end
cases.run('snapshot failures do not silently return a shared model') do
  assert_raises(TypeError) { GameRoomSnapshot.copy(callback: -> {}) }
end
