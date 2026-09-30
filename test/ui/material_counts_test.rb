def _(text); text; end
def n_(singular, plural, count); count == 1 ? singular : plural; end
require_relative "../../lib/game_simulation"
require_relative "../../games/reversi"
require_relative "../../games/checkers"
require_relative "../../games/chess"
require_relative "../../games/makao"

def summary(game, replay, viewer = "observer")
  matches = game.game_shortcuts(replay, viewer).select { |item| item.key == "s" && item.modifiers.empty? }
  raise "missing or duplicated S" unless matches.length == 1
  shortcut = matches.first
  raise "counter must only announce" unless shortcut.kind == :announcement
  shortcut.message
end

players = %w[Alice Bob]
[GameRoomGames::Reversi.new, GameRoomGames::Checkers.new, GameRoomGames::Chess.new].each do |game|
  environment = GameRoomSimulation::Environment.new_game(game: game, players: players)
  replay = environment.replay
  original = Marshal.dump(replay)
  raise "observer and player counts differ" unless summary(game, replay) == summary(game, replay, "Alice")
  raise "counter changed replay" unless Marshal.dump(replay) == original
end

reversi = GameRoomGames::Reversi.new
environment = GameRoomSimulation::Environment.new_game(game: reversi, players: players)
raise "initial disc count" unless summary(reversi, environment.replay) == "Alice: 2; Bob: 2"
environment.step(environment.legal_actions.first)
raise "updated disc count" unless summary(reversi, environment.replay) == "Alice: 4; Bob: 1"

checkers = GameRoomGames::Checkers.new
[8, 10, 12].each do |size|
  replay = GameRoomSimulation::Environment.new_game(game: checkers, players: players, options: { "board_size" => size }).replay
  replay.board.each { |row| row.fill(nil) }
  replay.board[0][1] = "0k"
  replay.board[2][1] = "0m"
  replay.board[3][2] = "1m"
  replay.state[:capture_blockers] = [[1, 4]]
  raise "count included absent/deferred victim" unless summary(checkers, replay) == "Alice: men: 1, kings: 1; Bob: men: 1, kings: 0"
end

chess = GameRoomGames::Chess.new
environment = GameRoomSimulation::Environment.new_game(game: chess, players: players)
raise "initial chess count" unless summary(chess, environment.replay).include?("kings: 1, queens: 1, rooks: 2, bishops: 2, knights: 2, pawns: 8")
environment.replay.board[0][0] = nil
raise "captured chess figure still counted" unless summary(chess, environment.replay).start_with?("Alice: kings: 1, queens: 1, rooks: 1")

makao = GameRoomGames::Makao.new
replay = GameRoomSimulation::Environment.new_game(game: makao, players: players).replay
raise "counter leaked into card game" if makao.game_shortcuts(replay, "Alice").any? { |item| item.label == "read the remaining pieces of each player" }
puts "Material counts: OK"
