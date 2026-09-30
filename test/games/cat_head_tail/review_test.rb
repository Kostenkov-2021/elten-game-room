require_relative "../../support/sequence_random"

require_relative "../../support/cat_head_tail"

# The reviewed changes must not turn every final-round tie into a gamble.
game = GameRoomGames::CatHeadTail.new
players = %w[Alice Bob]
failures = []
check = lambda do |name, &block|
  begin
    block.call
    puts "PASS #{name}"
  rescue StandardError => error
    failures << "#{name}: #{error.class}: #{error.message}"
    puts "FAIL #{failures.last}"
  end
end
choose = lambda do |replay|
  game.bot_strategy.choose(
    actions: game.legal_actions(replay, replay.current_player),
    actor: replay.current_player,
    random_source: GameRoomRandom::SequenceSource.new([]),
    replay: replay
  ).fetch("action")
end
prefix = [cht_event(1, "Alice", "roll", "2"), cht_event(2, "Alice", "bank")]
secure_events = prefix + [cht_event(3, "Bob", "roll", "2")]

check.call("last bot improves an already secured tie without risking the bank") do
  replay, = cht_replay(game, players, secure_events, score_limit: 2)
  assert(choose.call(replay) == "roll", "the bot settled for a secured tie")
  bust, = cht_replay(game, players, secure_events + [cht_event(4, "Bob", "roll", "1")], score_limit: 2)
  assert(bust.finished? && bust.draw, "a bust lost the secured tie")
  gain_events = secure_events + [cht_event(4, "Bob", "roll", "3")]
  gain, = cht_replay(game, players, gain_events, score_limit: 2)
  assert(choose.call(gain) == "bank", "the bot did not take the available victory")
  win, = cht_replay(game, players, gain_events + [cht_event(5, "Bob", "bank")], score_limit: 2)
  assert(win.winner == "Bob", "improving and banking did not win")
end

check.call("negative tail cannot make the bot bank away its secured tie") do
  events = secure_events + [cht_event(4, "Bob", "roll", "8|minus")]
  negative, = cht_replay(game, players, events, score_limit: 2)
  assert(choose.call(negative) == "roll", "the bot banked a negative turn")
  bust, = cht_replay(game, players, events + [cht_event(5, "Bob", "roll", "1")], score_limit: 2)
  assert(bust.draw, "clearing a negative tail lost the banked tie")
end

check.call("a tie that still needs banking is preserved") do
  events = [cht_event(1, "Alice", "roll", "6"), cht_event(2, "Alice", "bank"), cht_event(3, "Bob", "roll", "6")]
  replay, = cht_replay(game, players, events, score_limit: 6)
  assert(replay.state[:scores]["Bob"] == 0, "fixture already secured the tie")
  assert(choose.call(replay) == "bank", "the bot gambled an unsecured tie")
end

check.call("a negative turn does not give away an already banked victory") do
  events = prefix + (3..7).map { |id| cht_event(id, "Bob", "roll", "2") }
  events << cht_event(8, "Bob", "roll", "8|minus")
  replay, = cht_replay(game, players, events, score_limit: 2)
  assert(replay.state[:scores]["Bob"] + replay.state[:turn_points] == 2, "fixture did not offer a losing bank")
  assert(choose.call(replay) == "roll", "the bot banked away a secured victory")
  recovered, = cht_replay(game, players, events + [cht_event(11, "Bob", "roll", "1")], score_limit: 2)
  assert(recovered.winner == "Bob", "bust did not preserve the banked victory")
end

check.call("winning bank and non-final seating keep the author's decisions") do
  replay, = cht_replay(game, players, secure_events + [cht_event(4, "Bob", "roll", "2")], score_limit: 2)
  assert(choose.call(replay) == "bank", "the bot gambled a secured victory")
  earlier, = cht_replay(game, %w[Alice Bob Carol], secure_events, score_limit: 2)
  assert(choose.call(earlier) == "bank", "the last-seat exception affected an earlier player")
end

check.call("malformed rolls neither crash nor change state or last roll") do
  valid = [cht_event(1, "Alice", "roll", "6")]
  expected, = cht_replay(game, players, valid)
  [nil, "", "0", "9", "-1", "8", "8|", "8|other", "8|plus|minus", "2|plus", "garbage"].each do |value|
    replay, = cht_replay(game, players, valid + [cht_event(2, "Alice", "roll", value)])
    assert(replay.state == expected.state, "invalid roll changed state: #{value.inspect}")
    assert(replay.accepted_events.length == 1 && replay.history == expected.history, "invalid roll entered history")
  end
  other, = cht_replay(game, players, valid + [cht_event(2, "Bob", "roll", "8|plus")])
  assert(other.state == expected.state, "out-of-turn roll changed state")
end

check.call("D reads the latest accepted roll and roller after a turn changes") do
  empty, = cht_replay(game, players, [])
  message = game.shortcut_feature_data(:last_roll, empty, "observer")
  assert(message && message[:message] == "The dice have not been rolled.", "empty D has no useful message")
  events = [cht_event(1, "Alice", "roll", "6"), cht_event(2, "Alice", "bank")]
  replay, = cht_replay(game, players, events)
  assert(game.shortcut_feature_data(:last_roll, replay, "Bob")[:message] == "Alice, 6.", "D lost the previous roller")
  replay, = cht_replay(game, players, events + [cht_event(3, "Bob", "roll", "8|minus")])
  assert(game.shortcut_feature_data(:last_roll, replay, "observer")[:message] == "Bob, 8, -8 points.", "D lost the tail outcome")
  assert(game.game_shortcuts(replay, "observer").any? { |shortcut| shortcut.key == "d" && shortcut.message }, "D absent for observers")
end

check.call("two and eight seats complete the final circuit exactly once") do
  [2, 8].each do |count|
    seats = (1..count).map { |index| "Player#{index}" }
    events = [cht_event(1, seats.first, "roll", "3"), cht_event(2, seats.first, "bank")]
    seats.drop(1).each { |seat| events << cht_event(events.length + 1, seat, "bank") }
    replay, repository, session = cht_replay(game, seats, events, score_limit: 3)
    assert(replay.finished? && replay.winner == seats.first, "wrong last-circuit winner at #{count} seats")
    assert(replay.history.count { |entry| entry.key.to_s.start_with?("result:") } == 1, "result repeated")
    same = game.replay(session, events + [cht_event(events.length + 1, seats.first, "roll", "2")], repository)
    assert(same.state == replay.state && same.accepted_events == replay.accepted_events, "post-game roll accepted")
    assert(game.legal_actions(replay, seats.first).empty?, "finished player can still move")
    assert(game.surface_spec(replay, "observer").zones.first.cards.empty?, "observer can change finished game")
  end
end

raise failures.join("\n") unless failures.empty?
puts "PASS Cat, head, tail review regressions (8 cases)"
