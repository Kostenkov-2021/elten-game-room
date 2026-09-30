require_relative "../../../games/spades"
require_relative "../../../lib/game_simulation"
require_relative "../../support/assertions"
require_relative "../../support/spades_decision_contract"
include GameRoomTest::Assertions

directory = File.expand_path("../../fixtures/contracts/v1", __dir__)
item = JSON.parse(File.read(File.join(directory, 'histories.json'))).fetch('cases').find { |entry| entry.fetch('game') == 'spades' }
expected = JSON.parse(File.read(File.join(directory, 'spades-decisions.json')))
actual = GameRoomTest::SpadesDecisionContract.capture(GameRoomGames::Spades.new, item)
assert_equal(expected, actual, 'Spades decisions, candidate order or RNG changed')
puts 'PASS Spades baseline decisions: fair/omniscient, bids/plays, candidate order and RNG'
