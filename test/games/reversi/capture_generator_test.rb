require_relative '../../../games/reversi'
require_relative '../../../lib/game_simulation'
require_relative '../../support/assertions'
include GameRoomTest::Assertions

def reference_flips(board, x, y, marker)
  return [] if board[y][x]
  GameRoomGames::Reversi::DIRECTIONS.flat_map do |dx, dy|
    ray = (1...8).map { |n| [x + dx * n, y + dy * n] }
      .take_while { |cx, cy| cx.between?(0, 7) && cy.between?(0, 7) }
    captured = ray.take_while { |cx, cy| board[cy][cx] == 1 - marker }
    stop = ray[captured.length]
    !captured.empty? && stop && board[stop[1]][stop[0]] == marker ? captured : []
  end
end

game = GameRoomGames::Reversi.new
checks = 0
[false, true].product([false, true]).each do |passing, capture|
  env = GameRoomSimulation::Environment.new_game(game: game, players: %w[Alice Bob], seed: 137,
    options: {'allow_passing' => passing, 'mandatory_capture' => capture})
  random = Random.new(991)
  60.times do
    replay = env.replay
    before = Marshal.dump(replay.board)
    [0, 1].each do |marker|
      8.times do |y|
        8.times do |x|
          expected = reference_flips(replay.board, x, y, marker)
          assert(game.send(:flips_for, replay.board, x, y, marker) == expected, 'flip content/order differs')
          legal = if replay.board[y][x] != nil
            false
          elsif capture
            !expected.empty?
          else
            GameRoomGames::Reversi::DIRECTIONS.any? do |dx, dy|
              cx, cy = x + dx, y + dy
              cx.between?(0, 7) && cy.between?(0, 7) && replay.board[cy][cx] != nil
            end
          end
          assert(game.send(:legal_placement?, replay.board, x, y, marker, replay.state[:options]) == legal, 'legal placement differs')
          checks += 1
        end
      end
    end
    assert(Marshal.dump(replay.board) == before, 'generator mutated board')
    break if env.finished?
    actions = env.legal_actions
    assert(env.step(actions[random.rand(actions.length)]) == :ok, 'generated move was rejected')
  end
end
game.define_singleton_method(:flips_for) { |*| raise 'predicate materialized flips' }
board = game.send(:initial_board)
assert(game.send(:legal_placement?, board, 3, 2, 0, {'mandatory_capture' => true}), 'legal opening move rejected')
assert(!game.send(:legal_placement?, board, 0, 0, 0, {'mandatory_capture' => true}), 'empty capture accepted')
puts "PASS Reversi capture generator: #{checks} reference comparisons, all variants, order, pure board and short predicate"
