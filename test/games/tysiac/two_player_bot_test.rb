require_relative "../../support/tysiac_two_player"

def planner_for(game, replay, actor, seed = 13)
  TysiacPlanning::Planner.new(game, replay, actor, GameRoomRandom::SeededSource.new(seed))
end

def assert_sampled_partition(game, replay, actor, world)
  assert(world, "two-player planner fell back because sampling failed")
  played = game.send(:bot_public_played_cards, replay)
  partition = world[:hands].values.flatten + world[:set_aside] + played
  assert(partition.sort == game.send(:deck).sort, "sampled world lost or duplicated cards")
  assert(world[:hands][actor] == replay.state[:hands][actor], "sample changed bot hand")
  replay.state[:hands].each { |player, cards| assert(world[:hands][player].length == cards.length, "wrong sampled hand length") }
end

[2, 3].product([false, true]).each do |size, award|
  fixture = TwoPlayerTysiacFixture.new(size: size, award: award)
  game = fixture.game
  fixture.deal
  replay = fixture.replay
  bidder = replay.current_player
  planner = planner_for(game, replay, bidder)
  worlds = planner.send(:sampled_bidding_worlds, 4)
  assert(worlds.length == 4, "two-player bidding samples missing")
  worlds.each do |world|
    simulation = planner.send(:prepare_bidding_world, world, 100)
    assert(simulation[:hands].values.all? { |cards| cards.length == 12 - size }, "bidding simulation distributes cards to opponent")
    assert(simulation[:set_aside].length == size * 2, "bidding simulation lost a talon")
    points = simulation[:set_aside].sum { |c| game.class::CARD_POINTS.fetch(c[0]) }
    # Force no marriages to compare exact card points with the real engine.
    until simulation[:current_player] == nil
      actor = simulation[:current_player]
      card = planner.send(:legal_cards, simulation, actor).first
      assert(planner.send(:play_card, simulation, actor, "normal", card), "simulation rejected legal card")
    end
    assert(simulation[:round_points].values.sum == (award ? 120 : 120 - points), "simulated last-trick rule differs from engine")
  end
  selected = planner.choose_bid(game.legal_actions(replay, bidder), samples: 4)
  assert(game.legal_actions(replay, bidder).include?(selected), "no planned auction bid")
  fixture.move({ "kind" => "command", "action" => "bid", "bid" => 100 })
  fixture.move({ "kind" => "command", "action" => "bid", "bid" => "pass" })
  replay = fixture.replay
  talon_choice = game.bot_strategy.choose(actions: game.legal_actions(replay, bidder), actor: bidder,
    random_source: GameRoomRandom::SeededSource.new(8), game: game, replay: replay)
  assert(game.legal_actions(replay, bidder).include?(talon_choice), "bot cannot choose talon")
  fixture.move(talon_choice)
  size.times do |index|
    replay = fixture.replay
    planner = planner_for(game, replay, bidder)
    worlds = planner.send(:sampled_worlds, 4)
    assert(worlds.length == 4, "discard samples missing")
    worlds.each { |world| assert_sampled_partition(game, replay, bidder, world) }
    # Exercise the production strategy budget without surrendering this test
    # deal so all following phases can be checked as well.
    actions = game.legal_actions(replay, bidder).reject { |action| action["action"] == "surrender" }
    chosen = game.bot_strategy.choose(actions: actions, actor: bidder,
      random_source: GameRoomRandom::SeededSource.new(index + 41), game: game, replay: replay)
    assert(actions.include?(chosen), "bot cannot discard a card")
    fixture.move(chosen)
  end
  replay = fixture.replay
  selected = planner_for(game, replay, bidder).choose_contract(game.legal_actions(replay, bidder), samples: 4)
  assert(game.legal_actions(replay, bidder).include?(selected), "no planned final contract")
  fixture.move(selected)
  steps = 0
  while fixture.replay.state[:phase] == :playing
    replay = fixture.replay
    actor = replay.current_player
    planner = planner_for(game, replay, actor, steps + 1)
    world = planner.send(:sampled_worlds, 1).first
    assert_sampled_partition(game, replay, actor, world)
    if actor == bidder
      assert((replay.state[:discarded_cards] - world[:set_aside]).empty?, "bot forgot own discards")
    else
      assert((replay.state[:talon] - game.send(:bot_public_played_cards, replay) - world[:hands][bidder] - world[:set_aside]).empty?, "sample ignores revealed talon")
    end
    actions = game.legal_actions(replay, actor)
    selected = planner.choose_play(actions, samples: 4)
    assert(actions.include?(selected), "no planned card move")
    fixture.move(selected)
    steps += 1
    assert(steps <= 20, "bot round stalled")
  end
  assert(fixture.replay.state[:trick_number] == 12 - size, "bot round incomplete")
end

# Hidden cards may be rearranged freely when public knowledge is identical.
fixture = TwoPlayerTysiacFixture.new
fixture.auction
fixture.choose
3.times { fixture.discard }
fixture.move({ "kind" => "command", "action" => "contract", "bid" => 100 })
game, original = fixture.game, fixture.replay
%w[Alice Bob].each do |actor|
  changed = Marshal.load(Marshal.dump(original))
  opponent = (fixture.players - [actor]).first
  if actor == "Bob"
    # Bob is the bidder: all unseen cards are Alice's hand and unused talon.
    changed.state[:hands][opponent][0], changed.state[:set_aside][0] = changed.state[:set_aside][0], changed.state[:hands][opponent][0]
  else
    # Alice is the defender: only exchange unrevealed cards between the
    # bidder's remaining hand and his discards, preserving public talon data.
    hand = changed.state[:hands][opponent]
    discards = changed.state[:discarded_cards]
    i = hand.index { |card| !changed.state[:talon].include?(card) }
    j = discards.index { |card| !changed.state[:talon].include?(card) }
    assert(i && j, "hidden-information fixture unsuitable")
    reserve_index = changed.state[:set_aside].index(discards[j])
    hand[i], discards[j] = discards[j], hand[i]
    changed.state[:set_aside][reserve_index] = discards[j]
    changed.accepted_events.each do |event|
      next unless event["action"] == "discard_card" && event["value"] == hand[i]
      event["value"] = discards[j]
    end
  end
  assert(game.bot_observation(original, actor) == game.bot_observation(changed, actor), "observation exposes hidden cards")
  worlds1 = planner_for(game, original, actor).send(:sampled_worlds, 4)
  worlds2 = planner_for(game, changed, actor).send(:sampled_worlds, 4)
  assert(worlds1.length == 4 && worlds1 == worlds2, "planner peeks at hidden cards/events")
end

# A known, small ending: keeping the trump for the last trick wins the
# reserve and fulfils the contract. Taking the first trick with it fails.
state = game.send(:initial_state, fixture.players, game.normalize_options("variant" => "two_players"))
state.merge!(phase: :playing, current_player: "Bob", taker: "Bob", contract: 100, trick_number: 7, trump: "H",
  hands: { "Alice" => %w[AS 9C], "Bob" => %w[AH KS] }, round_points: { "Alice" => 5, "Bob" => 55 },
  set_aside: %w[AC TC TH TD], discarded_cards: [])
replay = GameRoomGames::Replay.new(players: fixture.players, state: state, current_player: "Bob", accepted_events: [], history: [])
planner = planner_for(game, replay, "Bob")
world = planner.send(:world_from_state, hands: Marshal.load(Marshal.dump(state[:hands])))
world[:set_aside] = state[:set_aside].dup
planner.define_singleton_method(:sampled_worlds) { |_count| [Marshal.load(Marshal.dump(world))] }
actions = game.legal_actions(replay, "Bob")
assert(planner.send(:late_contract_control_actions, actions) == actions, "ace shortcut hides last-trick choice")
assert(planner.choose_play(actions, samples: 1)["card"] == "normal|KS", "bot gives away last trick reserve")

puts "PASS two-player bot: talons, discarding, bidding, both scoring rules, legal play and information isolation"
