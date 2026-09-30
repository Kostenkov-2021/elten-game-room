require_relative '../../../games/checkers'
require_relative '../../../lib/game_simulation'
require_relative '../../support/assertions'
include GameRoomTest::Assertions

game = GameRoomGames::Checkers.new
counting = false
constructor = GameRoomGames::BoardMove.method(:new)
GameRoomGames::BoardMove.define_singleton_method(:new) do |**options|
  raise 'mobility materialized a BoardMove' if counting
  constructor.call(**options)
end
checks = 0
[8, 10, 12].each do |size|
  state = game.send(:initial_state, %w[Alice Bob], game.normalize_options('board_size' => size))
  board = Array.new(size) { Array.new(size) }
  [[0, 0, '0m'], [2, 2, '0k'], [3, 3, '1m'], [5, 5, '1k'], [6, 2, '1m'], [2, 6, '0m']].each { |x, y, code| board[y][x] = code }
  [state[:board], board].each do |position|
    512.times do |rules|
      candidate = state.merge(board: position, rules: rules, capture_blockers: [[4, 4], [1, 1]])
      [0, 1].each do |marker|
        expected = game.send(:raw_moves, candidate, marker).length + game.send(:raw_captures, candidate, marker).length
        before = Marshal.dump(candidate)
        counting = true
        actual = game.send(:raw_mobility, candidate, marker)
        counting = false
        assert(actual == expected, "mobility differs: size=#{size} rules=#{rules} marker=#{marker}")
        assert(Marshal.dump(candidate) == before, 'mobility mutated state')
        checks += 1
      end
    end
  end
end
puts "PASS Checkers mobility: #{checks} comparisons, all rule bitsets/sizes, kings, blockers and no move materialization"
