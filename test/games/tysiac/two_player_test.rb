require_relative "../../support/tysiac_two_player"

game = GameRoomGames::Tysiac.new
assert(game.minimum_players == 2 && game.maximum_players == 3, "two-player Tysiac unavailable")
assert(game.default_options["variant"] == "three_players", "three-player default changed")
assert(game.validation_error({}, player_count: 3) == nil, "old table rejected")
assert(game.validation_error({}, player_count: 2) != nil, "three-player table started with two")
assert(game.validation_error({ "variant" => "two_players" }, player_count: 2) == nil, "two-player table rejected")
assert(game.validation_error({ "variant" => "two_players" }, player_count: 3) != nil, "two-player table started with three")
%w[talon_size last_trick_talon].each do |key|
  definition = game.option_definitions.find { |item| item.key == key }
  assert(definition && !game.option_visible?(definition, {}) && game.option_visible?(definition, { "variant" => "two_players" }), "dependent option #{key}")
end

[2, 3].product([false, true], [0, 1]).each do |size, award, chosen|
  fixture = TwoPlayerTysiacFixture.new(size: size, award: award)
  replay = fixture.deal
  count = 12 - size
  assert(replay.state[:hands].values.map(&:length) == [count, count], "wrong hand sizes")
  assert(replay.state[:talons].map(&:length) == [size, size], "wrong talons")
  all = replay.state[:hands].values.flatten + replay.state[:talons].flatten
  assert(all.sort == game.send(:deck).sort && all.uniq.length == 24, "deal lost or duplicated cards")
  fixture.move({ "kind" => "command", "action" => "bid", "bid" => 100 })
  replay = fixture.move({ "kind" => "command", "action" => "bid", "bid" => "pass" })
  assert(replay.state[:phase] == :choosing_talon && replay.current_player == "Bob", "auction did not offer talons")
  assert(!replay.state[:talon_visible] && replay.state[:hands]["Bob"].length == count, "talon taken before choice")
  surface = game.surface_spec(replay, "Bob")
  assert(surface.options.map(&:value) == %w[0 1], "two blind talon choices missing")
  assert(game.playable_card_navigation(replay, "Bob") == nil, "Z played a card during talon choice")
  talons = replay.state[:talons].map(&:dup)
  replay = fixture.choose(chosen)
  assert(replay.state[:phase] == :discarding && replay.state[:hands]["Bob"].length == 12, "chosen talon not added")
  assert(replay.state[:talon] == talons[chosen] && replay.state[:set_aside] == talons[1 - chosen], "wrong talon retained")
  assert(game.legal_actions(replay, "Bob").any? { |action| action["action"] == "surrender" }, "cannot surrender before discarding")
  discarded = size.times.map { fixture.discard }
  replay = fixture.replay
  assert(replay.state[:phase] == :contract && replay.state[:hands].values.all? { |hand| hand.length == count }, "wrong discard count")
  assert(replay.state[:set_aside].sort == (talons[1 - chosen] + discarded).sort, "missing set-aside cards")
  assert(!game.legal_actions(replay, "Bob").any? { |action| action["action"] == "surrender" }, "late surrender")
  assert(game.history_entries_for_display(replay, "Bob").select { |e| e.kind == :discard_card }.map(&:text).join.include?(game.send(:card_label, discarded.first)), "own discard history missing")
  ["Alice", "Observer"].each do |viewer|
    messages = game.history_entries_for_display(replay, viewer).select { |e| e.kind == :discard_card }.map(&:text).join
    assert(discarded.none? { |card| messages.include?(game.send(:card_label, card)) }, "private discard exposed")
    assert(game.bot_observation(replay, viewer)["discarded_cards"].to_a.empty?, "bot sees another player's discards")
  end
  fixture.move({ "kind" => "command", "action" => "contract", "bid" => 100 })
  set_aside_points = replay.state[:set_aside].sum { |card| GameRoomGames::Tysiac::CARD_POINTS.fetch(card[0]) }
  until fixture.replay.state[:phase] != :playing
    replay = fixture.replay
    action = game.legal_actions(replay, replay.current_player).find { |a| a["card"].start_with?("normal|") }
    fixture.move(action)
  end
  replay = fixture.replay
  assert(replay.state[:trick_number] == count && replay.state[:hands].values.all?(&:empty?), "round ended after wrong number of tricks")
  assert(replay.history.count { |entry| entry.kind == :trick } == count, "wrong trick count")
  expected = award ? 120 : 120 - set_aside_points
  assert(replay.state[:round_points].values.sum == expected, "wrong round total with option #{award}")
  entries = replay.history.select { |entry| entry.kind == :set_aside }
  assert(entries.length == (award ? 1 : 0), "wrong bonus announcements")
  if award
    last = replay.history.select { |entry| entry.kind == :trick }.last.actor
    assert(entries.first.actor == last && entries.first.value.to_i == set_aside_points, "bonus assigned to someone other than last trick winner")
  end
  # New peers reconstruct precisely the same state. Repeated/stale commands
  # cannot take a second talon, discard extra cards or award points twice.
  assert(fixture.replay.state == replay.state, "replay is not deterministic")
  before = replay.accepted_events.length
  fixture.event("Bob", "take_talon", 1 - chosen)
  fixture.event("Bob", "discard_card", discarded.first)
  assert(fixture.replay.accepted_events.length == before, "stale actions accepted")
  assert(fixture.replay.state == replay.state, "stale actions changed state")
  fixture.event("Alice", "deal", "2|1|111102030405060708090a0b0c0d0e0f")
  assert(fixture.replay.state[:round] == 2 && fixture.replay.current_player == "Alice", "dealer did not alternate")
  assert(fixture.replay.state[:set_aside].empty? && fixture.replay.state[:discarded_cards].empty?, "previous talon survived next deal")
end

fixture = TwoPlayerTysiacFixture.new(size: 2)
fixture.auction
before = fixture.replay
[-1, 2, "0|1", "", "01"].each { |value| fixture.event("Bob", "take_talon", value) }
fixture.event("Alice", "take_talon", 0)
fixture.event("Bob", "discard_card", before.state[:hands]["Bob"].first)
assert(fixture.replay.state == before.state && fixture.replay.accepted_events == before.accepted_events, "invalid talon choice changed state")
fixture.choose
before = fixture.replay
fixture.event("Bob", "take_talon", 1)
fixture.event("Bob", "contract", 100)
fixture.event("Bob", "pass_card", "Alice|#{before.state[:hands]["Bob"].first}")
fixture.event("Alice", "discard_card", before.state[:hands]["Alice"].first)
fixture.event("Bob", "discard_card", "XX")
assert(fixture.replay.state == before.state && fixture.replay.accepted_events == before.accepted_events, "invalid discard/early contract changed state")
fixture.discard
before = fixture.replay
fixture.event("Bob", "surrender", "")
assert(fixture.replay.state == before.state, "surrender accepted after first discard")

fixture = TwoPlayerTysiacFixture.new
fixture.auction
fixture.choose
replay = fixture.move({ "kind" => "command", "action" => "surrender" })
assert(replay.state[:phase] == :round_complete && replay.state[:scores] == { "Alice" => 60, "Bob" => 0 }, "two-player surrender scoring changed")
assert(replay.history.none? { |entry| entry.kind == :set_aside }, "surrender awarded unplayed last trick")

puts "PASS two-player Tysiac: both talon sizes/choices, options, replay, privacy, invalid actions, surrender and last-trick points"
