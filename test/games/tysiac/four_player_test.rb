require_relative "../../support/tysiac_four_player"

fixture = FourPlayerTysiacFixture.new
game = fixture.game
rests = []
4.times do
  replay = fixture.next_deal
  resting = replay.state[:resting_player]
  rests << resting
  assert(replay.state[:hands][resting].empty?, "resting player received cards")
  assert(game.legal_actions(replay, resting).empty?, "resting player can act")
  assert(game.shortcut_feature_data(:hand, replay, resting)[:message].include?("sit out"), "rest missing from hand announcement")
  assert(replay.state[:hands].values.flatten.length == 21 && replay.state[:talon].length == 3, "four-player deal size")
  fixture.finish_auction
  assert(game.send(:pass_recipients, fixture.replay.state).length == 2, "resting player in passes")
  before = fixture.replay.state
  idle = %i[scores barrels zero_rounds surrender_uses].to_h { |key| [key, Marshal.load(Marshal.dump(before[key][resting]))] }
  fixture.pass_cards
  assert(fixture.replay.state[:hands].values.map(&:length).sort == [0, 8, 8, 8], "four-player final hands")
  fixture.finish_play
  state = fixture.replay.state
  assert(state[:trick_number] == 8 && state[:round_points].values.sum == 120, "four-player full deal failed")
  idle.each { |key, value| assert(state[key][resting] == value, "rest counted in #{key}") }
  assert(fixture.replay.history.any? { |item| item.kind == :rest && item.actor == resting }, "no resting announcement")
end
assert(rests.uniq.length == 4, "rest did not rotate across all seats")

fixture = FourPlayerTysiacFixture.new(variant: "teams", seats: [0, 0, 1, 1])
game = fixture.game
replay = fixture.next_deal
assert(replay.state[:round_players] == %w[Alice Carol Bob David], "partners not seated opposite")
assert(replay.state[:hands].values.all? { |hand| hand.length == 5 } && replay.state[:talon].length == 4, "team deal sizes")
assert((replay.state[:hands].values.flatten + replay.state[:talon]).sort == game.send(:deck).sort, "bad team partition")
fixture.move({"kind" => "command", "action" => "bid", "bid" => 100})
fixture.move({"kind" => "command", "action" => "bid", "bid" => "pass"})
assert(fixture.replay.current_player == "David", "partner bidder turn not available")
fixture.move({"kind" => "command", "action" => "bid", "bid" => 105})
fixture.move({"kind" => "command", "action" => "bid", "bid" => "pass"}) while fixture.replay.state[:phase] == :bidding
assert(fixture.replay.state[:taker] == "David", "partner cannot overbid")
assert(fixture.replay.state[:hands]["David"].length == 9, "team bidder did not take four")
fixture.pass_cards
replay = fixture.replay
assert(replay.state[:hands].values.all? { |hand| hand.length == 6 }, "team passing did not produce six each")
assert(replay.state[:hands].values.flatten.sort == game.send(:deck).sort, "team pass lost card")
assert(replay.accepted_events.count { |event| event["action"] == "pass_card" } == 3, "not three private passes")
fixture.move({"kind" => "command", "action" => "contract", "bid" => 105})
while fixture.replay.state[:phase] == :playing
  replay = fixture.replay
  fixture.move(game.legal_actions(replay, replay.current_player).find { |a| a["card"].start_with?("normal|") })
end
state = fixture.replay.state
assert(state[:trick_number] == 6 && state[:round_points].values.sum == 120, "team complete deal")
assert(state[:scores].keys == %w[team:0 team:1], "team score stored per individual")
assert(game.participant_scores(fixture.replay)["Alice"] == game.participant_scores(fixture.replay)["Bob"], "partner scores differ")
assert(game.bot_allied?(fixture.replay, "Alice", "Bob") && !game.bot_allied?(fixture.replay, "Alice", "Carol"), "bot alliances incorrect")
assert(game.shortcut_feature_data(:scores, fixture.replay, "Alice")[:message].scan(/Team /).length == 2, "score read twice per team")
assert(game.bot_observation(fixture.replay, "Alice")["hand"] == [], "wrong observation")
puts "PASS four-player Tysiac: four complete rotating deals, team deal/auction/passing/play, shared score and public presentation"
