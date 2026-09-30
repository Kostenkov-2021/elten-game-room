require_relative '../../support/background_help_game_screen'
require_relative '../../support/native_public_messages'
require_relative '../../../games/scrabble'

# Exercise the whole normal wait loop, not just calling Preview#tick directly.
# The first live attempt found its missing refresh_due? contract here.
h, screen = screen_fixture(GameRoomGames::Scrabble.new)
frames = 0
client = nil
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 8
Form.driver = lambda do |_form|
  raise 'Scrabble screen did not reach its normal wait' if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
  client = screen.instance_variable_get(:@game_client)
  if client && client.instance_variable_get(:@replay)&.state&.[](:phase) == :playing
    frames += 1
    assert(client.refresh_due? == false, 'A preview requested a whole form rebuild')
    client.automatic_error(:stale)
    screen.instance_variable_get(:@layout).back_button.trigger(:press) if frames >= 40
  end
  sleep 0.002
end
h.as('Alice') { assert(screen.run == :back, 'Scrabble preview changed normal exit') }
assert(frames >= 40, 'The screen timer was never exercised after dealing')
assert(client.instance_variable_get(:@closed), 'Closing the screen leaked its preview client')
assert(client.instance_variable_get(:@progress).closed?, 'Closing the screen leaked its preview timer')
puts 'PASS Scrabble preview through real GameScreen run/wait, automatic deal, refresh contract and shutdown'
