require_relative '../../../games/chess'
require_relative '../../../lib/game_simulation'
require_relative '../../support/assertions'
include GameRoomTest::Assertions

game = GameRoomGames::Chess.new
env = GameRoomSimulation::Environment.new_game(game: game, players: %w[Alice Bob], seed: 137)
states = []
random = Random.new(83)
80.times do
  states << env.replay.state
  break if env.finished?
  actions = env.legal_actions
  assert(env.step(actions[random.rand(actions.length)]) == :ok, 'fixture action rejected')
end
special = game.send(:initial_state, %w[Alice Bob])
special[:board] = Array.new(8) { Array.new(8) }
[[4, 0, 'wK'], [0, 0, 'wR'], [7, 0, 'wR'], [4, 7, 'bK'], [0, 7, 'bR'], [7, 7, 'bR'],
 [3, 4, 'wP'], [4, 4, 'bP'], [1, 6, 'wP']].each { |x, y, code| special[:board][y][x] = code }
special[:en_passant] = [4, 5]
states << special
assert(game.send(:pseudo_moves, special, 'w').any? { |move| move.metadata.key?('castle') }, 'fixture lacks castling')
assert(game.send(:pseudo_moves, special, 'w').any? { |move| move.metadata.key?('en_passant') }, 'fixture lacks en passant')
counting = false
constructor = GameRoomGames::BoardMove.method(:new)
GameRoomGames::BoardMove.define_singleton_method(:new) do |**options|
  raise 'mobility materialized a BoardMove' if counting
  constructor.call(**options)
end
states.each do |state|
  %w[w b].each do |colour|
    expected = game.send(:pseudo_moves, state, colour).length
    before = Marshal.dump(state)
    counting = true
    actual = game.send(:pseudo_move_count, state, colour)
    counting = false
    assert(actual == expected, 'pseudolegal mobility differs')
    assert(Marshal.dump(state) == before, 'mobility mutated state')
  end
end
puts "PASS Chess mobility: #{states.length * 2} comparisons, opening/midgame, castling/en passant/promotion and no move materialization"
