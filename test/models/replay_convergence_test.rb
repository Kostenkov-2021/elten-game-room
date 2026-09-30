require_relative "../support/native_room_harness"
require_relative "../../games/tic_tac_toe"
require_relative "../../games/four_in_a_row"

[GameRoomGames::TicTacToe, GameRoomGames::FourInARow].each do |type|
  harness = NativeRoomHarness.new(game: type.new, users: %w[Alice Bob])
  harness.start
  harness.assert_converged('initial')
  original = harness.method(:replay)
  %i[board players current_player winner draw history accepted_events].each do |field|
    harness.define_singleton_method(:replay) do |user|
      result = original.call(user)
      if user == 'Bob'
        case field
        when :board then result.board[0][0] = 1
        when :players then result.players = result.players.reverse
        when :current_player, :winner then result.public_send("#{field}=", 'Bob')
        when :draw then result.draw = true
        when :history then result.history = []
        when :accepted_events then result.accepted_events = [{'id' => 99}]
        end
      end
      result
    end
    error = assert_raises(RuntimeError) { harness.assert_converged('injected mismatch') }
    assert(error.message.include?(field.to_s), "#{type}: missed #{field}")
  end
  harness.define_singleton_method(:replay, original)
  harness.assert_converged('restored')
  snapshot = GameRoomTest::ReplaySnapshot.capture(harness.replay('Alice'))
  snapshot[:board][0][0] = 1
  assert(harness.replay('Alice').board[0][0].nil?, 'snapshot shares the board')
end
puts 'PASS semantic replay convergence: real nil-state boards, controlled mismatches and isolated snapshots'
