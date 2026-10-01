require_relative "../../support/tysiac_four_player"
game = GameRoomGames::Tysiac.new
players = %w[Alice Bob Carol David]
make_state = -> do
  state = game.send(:initial_state, players, game.normalize_options("variant" => "teams"))
  state.merge!(taker: "Alice", contract: 150, phase: :playing, round: 1)
  state
end
settle = ->(state, surrender = false) { history = []; game.send(:complete_round, state, 20, history, surrendered: surrender); history }
[[100, 70, 150], [80, 60, -150]].each do |own, partner, award|
  state = make_state.call
  state[:round_points] = {"Alice" => own, "Carol" => partner, "Bob" => 7, "David" => 5}
  settle.call(state)
  assert(state[:scores] == {"team:0" => award, "team:1" => 10}, "contract or single rounding incorrect")
end
state = make_state.call
state[:round_points]["Carol"] = 160
settle.call(state)
assert(state[:zero_rounds]["team:0"] == 0, "partner points counted as zero")

state = make_state.call
state[:contract] = 155
3.times do |index|
  state[:taker] = index.odd? ? "Carol" : "Alice"
  state[:phase] = :passing
  assert(game.send(:surrender_available?, state, state[:taker]), "early surrender forbidden")
  settle.call(state, true)
  assert(state[:scores]["team:1"] == (index + 1) * 80, "surrender award multiplied or rounding wrong")
  assert(state[:scores]["team:0"] == (index == 2 ? -120 : 0), "shared surrender counter wrong")
  assert(state[:zero_rounds].values.all?(&:zero?), "surrender counted as zero")
end
assert(state[:surrender_uses]["team:0"] == 0, "third surrender not reset")
state = make_state.call
state[:phase] = :passing
state[:barrels]["team:0"] = {active: true, deals_left: 2}
assert(!game.send(:surrender_available?, state, "Alice"), "team on barrel surrendered")
state[:barrels]["team:0"] = {active: false, deals_left: 0}
state[:barrels]["team:1"] = {active: true, deals_left: 2}
state[:scores]["team:1"] = 880
settle.call(state, true)
assert(state[:scores]["team:1"] == 880 && state[:barrels]["team:1"][:deals_left] == 2, "surrender consumed opponent barrel")
state = make_state.call
state[:scores]["team:0"] = 800
state[:contract] = 100
state[:round_points]["Carol"] = 100
history = settle.call(state)
assert(state[:scores]["team:0"] == 880 && state[:barrels]["team:0"] == {active: true, deals_left: 3}, "shared barrel entry")
assert(history.count { |item| item.kind == :barrel } == 1, "barrel announced per player")
state[:contract] = 120
state[:round_points]["Carol"] = 120
settle.call(state)
assert(state[:winner] == "team:0" && state[:scores]["team:0"] == 1000, "team win on barrel")

# The partner does not remove suit/trump duties, and no new overtake rule.
state = make_state.call
state[:current_player] = "Alice"
state[:trump] = "H"
state[:current_trick] = [{player: "Carol", card: "AS"}, {player: "David", card: "9S"}]
state[:hands]["Alice"] = %w[9H TS KS]
assert(game.send(:legal_cards, state, "Alice").sort == %w[KS TS], "partner changed following rule")
state[:hands]["Alice"] = %w[9H AH AC]
assert(game.send(:legal_cards, state, "Alice").sort == %w[9H AH], "partner changed trump rule")
state[:trick_number] = 1
state[:current_trick] = []
state[:hands]["Alice"] = ["KH"]
state[:hands]["Carol"] = ["QH"]
assert(!game.send(:marriage_available?, state, "Alice", "KH"), "marriage borrowed partner card")

state = game.send(:initial_state, players, game.normalize_options("variant" => "four_players"))
state.merge!(round_players: players.drop(1), resting_player: "Alice", taker: "Bob", contract: 100)
state[:barrels]["Alice"] = {active: true, deals_left: 1}
state[:scores]["Alice"] = 880
settle.call(state)
assert(state[:scores]["Alice"] == 880 && state[:barrels]["Alice"][:deals_left] == 1 && state[:zero_rounds]["Alice"] == 0, "rest used barrel or zero")
puts "PASS Tysiac shared contract, rounding, surrender cycles/minimum, barrel, zero, win and unchanged follow/trump rules"
