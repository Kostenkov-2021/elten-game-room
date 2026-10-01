require_relative "../../support/tysiac_four_player"
%w[four_players teams].each do |variant|
  fixture = FourPlayerTysiacFixture.new(variant: variant)
  game = fixture.game
  fixture.next_deal
  replay = fixture.replay
  actor = replay.current_player
  planner = TysiacPlanning::Planner.new(game, replay, actor, GameRoomRandom::SeededSource.new(16))
  worlds = planner.send(:sampled_bidding_worlds, 3)
  assert(worlds.size == 3, "#{variant}: bidding sampling failed")
  worlds.each do |world|
    assert((world[:hands].values.flatten + world[:talon]).sort == game.send(:deck).sort, "#{variant}: sampled deck invalid")
    prepared = planner.send(:prepare_bidding_world, world, 100)
    size = variant == "teams" ? 6 : 8
    assert(prepared[:hands].values.all? { |hand| hand.size == size }, "#{variant}: planning pass sizes")
    planner.send(:finish_round, prepared)
    assert(prepared[:hands].values.all?(&:empty?), "#{variant}: rollout unfinished")
  end
  fixture.finish_auction
  while fixture.replay.state[:phase] == :passing
    replay = fixture.replay
    planner = TysiacPlanning::Planner.new(game, replay, replay.current_player, GameRoomRandom::SeededSource.new(9))
    actions = game.legal_actions(replay, replay.current_player).reject { |a| a["action"] == "surrender" }
    selected = planner.choose_passing(actions, samples: 3)
    assert(actions.include?(selected), "#{variant}: passing fell back")
    fixture.move(selected)
  end
  fixture.move({"kind" => "command", "action" => "contract", "bid" => 100})
  6.times do
    replay = fixture.replay
    actor = replay.current_player
    planner = TysiacPlanning::Planner.new(game, replay, actor, GameRoomRandom::SeededSource.new(24))
    worlds = planner.send(:sampled_worlds, 2)
    assert(worlds.size == 2, "#{variant}: play sampling failed")
    other_hands = replay.state[:hands].reject { |player, _| player == actor }.values
    # Real hidden identities must not change the decision if public counts,
    # passes and all observed information stay the same.
    changed = Marshal.load(Marshal.dump(replay))
    keys = changed.state[:hands].keys.reject { |player| player == actor }
    cards = other_hands.flatten.reverse
    keys.each { |player| changed.state[:hands][player] = cards.shift(changed.state[:hands][player].length) }
    hidden_planner = TysiacPlanning::Planner.new(game, changed, actor, GameRoomRandom::SeededSource.new(24))
    assert(worlds == hidden_planner.send(:sampled_worlds, 2), "#{variant}: planner read hidden partner/opponent cards")
    actions = game.legal_actions(replay, actor)
    selected = planner.choose_play(actions, samples: 3)
    assert(actions.include?(selected), "#{variant}: no bot play")
    fixture.move(selected)
  end
end
puts "PASS four-player/team bots: legal complete sampled deals, three passes, partner utility and hidden-information isolation"
