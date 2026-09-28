require_relative 'support/background_help_game_screen'

$game_room_test_user = 'Alice'
h, screen = screen_fixture(GameRoomGames::FourInARow.new, bots: 0)
messages = []
Log.define_singleton_method(:debug) { |text| messages << text.to_s }
Form.driver = ->(_form) { screen.instance_variable_get(:@layout).back_button.trigger(:press) }
h.as('Alice') { assert(screen.run == :back, 'Exit failed') }
assert(messages.grep(/bot confirmation/).empty?, 'human-only UI produced a bot confirmation log')
assert(h.events('Alice').empty?, 'idle UI generated a move')
assert(screen.instance_variable_get(:@session_runner).nil?, 'runner leaked after closing the screen')
assert(!screen.respond_to?(:perform_bot_turn, true), 'obsolete UI bot executor remains reachable')
puts 'Normal human-only GameScreen produces no empty bot confirmations and closes the sole worker'
