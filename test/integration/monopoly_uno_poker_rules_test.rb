require_relative "../support/new_games_fixture"

results = []
check = lambda do |name, &test|
  test.call
  results << [name, "PASS"]
rescue StandardError => e
  results << [name, "FAIL", e.message]
end
def view(state)
  GameRoomGames::Replay.new(players: state[:players], current_player: state[:current_player],
    winner: state[:winner], accepted_events: [], history: [], state: state)
end
def initial(game, options = {})
  game.send(:initial_state, %w[Alice Bob Carol], game.normalize_options(options))
end
def best(game, state)
  game.legal_actions(view(state), "Alice").max_by { |a| game.bot_action_score(view(state), "Alice", a) }
end
monopoly = GameRoomGames::Monopoly.new
repo = NewGames116Repository.new(%w[Alice Bob Carol])
check.call("Monopoly: debt waits for the next own turn, including doubles") do
  state = initial(monopoly)
  state.update(phase: :turn_complete, extra_turn: true)
  monopoly.send(:pay_money, state, "Alice", "Bob", 1600)
  monopoly.send(:advance_completed_turn, state)
  assert(state[:current_player] == "Bob", "Insolvency holds the old turn")
  %w[Bob Carol].each do |actor|
    assert(state[:current_player] == actor, "Debt interrupted another player's turn")
    state[:phase] = :turn_complete
    monopoly.send(:advance_completed_turn, state)
  end
  assert(state[:current_player] == "Alice" && state[:phase] == :awaiting_roll, "No debt management on return")
  assert(monopoly.action_for({ "action" => "roll" }, view(state), "Alice", context: context_for).first == :insolvent_100, "Insolvent roll allowed")
  state[:owners][39] = "Alice"
  assert(monopoly.send(:apply_property_action, state, { "id" => 1, "action" => "mortgage", "value" => "39" }, "Alice", repo, []), "Mortgage refused")
  monopoly.send(:settle_debts, state)
  monopoly.send(:advance_completed_turn, state)
  assert(state[:current_player] == "Alice" && state[:cash]["Alice"] == 100, "Debt payment skipped the next own roll")
end
check.call("Monopoly: a card charging another player does not seize their turn") do
  state = initial(monopoly)
  state.update(phase: :turn_complete, extra_turn: true)
  state[:cash]["Bob"] = 0
  monopoly.send(:pay_money, state, "Bob", "Alice", 50)
  monopoly.send(:advance_completed_turn, state)
  assert(state[:current_player] == "Alice" && state[:phase] == :awaiting_roll, "Birthday debt stole the extra roll")
end
check.call("Monopoly: luxury tax deducts the exact amount on every board and announces it") do
  GameRoomContent::MonopolyBoards.choices.each do |choice|
    [true, false].each do |jackpot|
      state = initial(monopoly, "board" => choice.value, "free_parking_jackpot" => jackpot)
      tax = state[:board].find { |s| s[:type] == :tax_luxury }
      next unless tax
      state[:positions]["Alice"] = tax[:index]
      before = state[:cash]["Alice"]
      history = []
      monopoly.send(:resolve_square, state, "Alice", 1, history)
      assert(tax[:amount].to_i > 0 && state[:cash]["Alice"] == before - tax[:amount], "#{choice.value}: incorrect tax")
      assert(state[:jackpot] == (jackpot ? tax[:amount] : 0), "#{choice.value}: wrong jackpot")
      assert(history.any? { |h| h.text.include?(tax[:amount].to_s) && h.text.include?(tax[:name]) }, "Tax has no payment announcement")
    end
  end
end
check.call("Monopoly: build costs, existing houses and unavailable H") do
  state = initial(monopoly)
  %w[h k].each do |key|
    shortcut = monopoly.custom_game_shortcuts(view(state), "Alice").find { |s| s.key == key && s.modifiers.empty? }
    assert(shortcut && !shortcut.message.to_s.empty?, "Unavailable #{key} is silent")
  end
  state[:owners].merge!(1 => "Alice", 3 => "Alice")
  state[:houses][1] = 1
  assert(!monopoly.send(:can_build?, state, "Alice", state[:board][1]), "Uneven build allowed")
  assert(monopoly.send(:can_build?, state, "Alice", state[:board][3]), "Even build refused")
  text = monopoly.send(:action_label, { "action" => "build", "property" => "3" }, state, "Alice")
  assert(text.include?(state[:board][3][:house_cost].to_s) && text.include?("0"), "Build omits cost/count")
end
check.call("Monopoly: bot does not propose a one-sided or repeated trade") do
  state = initial(monopoly)
  state[:owners].merge!(1 => "Bob", 3 => "Alice")
  action = { "action" => "trade_offer", "offer" => "1|-1|1|60|0" }
  assert(monopoly.bot_action_score(view(state), "Alice", action) < 100, "Bot insists on buying an important property at face value")
  state[:owners][6] = "Alice"
  state[:cash]["Bob"] = 0
  choice = best(monopoly, state)
  if choice["action"] == "trade_offer"
    offer = monopoly.send(:parse_trade_offer, state, choice["offer"])
    assert(offer[:target] != "Bob" || offer[:give_cash] > offer[:receive_cash], "Bot tries to drain an insolvent target")
  end
end
poker = GameRoomGames::Poker.new
check.call("Monopoly: bot permits useful trades but stops after an offer and remembers rejection") do
  state = initial(monopoly)
  state[:owners].merge!(1 => "Alice", 3 => "Bob", 6 => "Alice", 8 => "Bob", 9 => "Bob")
  # Completing both groups does not make the bare exchange fair: Alice gives
  # away the more valuable last light-blue deed. Current valuation correctly
  # rejects that loss; compensation makes the gains positive for both sides.
  bare = { "action" => "trade_offer", "offer" => "1|6|3|0|0" }
  roll_score = monopoly.bot_action_score(view(state), "Alice", { "action" => "roll" })
  assert(monopoly.bot_action_score(view(state), "Alice", bare) < roll_score, "Bot gives away a valuable group blocker without compensation")
  value = monopoly.send(:encode_trade_offer, target: 1, give_property: 6, receive_property: 3, receive_cash: 300)
  action = { "action" => "trade_offer", "offer" => value }
  offer = monopoly.send(:parse_trade_offer, state, value).merge(from: "Alice")
  assert(%w[Alice Bob].all? { |player| monopoly.send(:trade_gain, state, offer, player) > 0 }, "Trade fixture is not mutually beneficial")
  assert(monopoly.bot_action_score(view(state), "Alice", action) > roll_score, "Mutually beneficial group completion is ignored")
  assert(monopoly.send(:apply_trade, state, { "id" => 1, "action" => "trade_offer", "value" => action["offer"] }, "Alice", repo, []), "Useful offer rejected")
  assert(monopoly.send(:apply_trade, state, { "id" => 2, "action" => "trade_reject" }, "Bob", repo, []), "Cannot reject offer")
  assert(best(monopoly, state)["action"] != "trade_offer", "Bot immediately bombards player with a different offer")
  state[:turn_number] += 20
  assert(monopoly.bot_action_score(view(state), "Alice", action) < -10_000, "Rejected offer returns on the next roll")
end
%w[holdem draw].each do |variant|
  check.call("Poker #{variant}: checking is not undervalued against raising") do
    state = initial(poker, "variant" => variant)
    state.update(phase: :betting, current_player: "Alice", street: 1, current_bet: 0)
    state[:contributions].transform_values! { 100 }
    cards = poker.send(:standard_deck)
    state[:players].each { |player| state[:hands][player] = cards.shift(variant == 'draw' ? 5 : 2) }
    # Against two opponents, 50% equity is a strong value-betting hand, not
    # an indifferent heads-up hand. Preserve checking below the fair 1/3 share.
    poker.define_singleton_method(:poker_equity) { |_state, _actor, **_options| 0.25 }
    assert(best(poker, state)["action"] == "check", "Mediocre hand raises when it could check")
    poker.define_singleton_method(:poker_equity) { |_state, _actor, **_options| 0.98 }
    assert(%w[raise all_in].include?(best(poker, state)["action"]), "Strong hand can no longer value bet")
    state[:current_bet] = 1400
    poker.define_singleton_method(:poker_equity) { |_state, _actor, **_options| 0.1 }
    assert(best(poker, state)["action"] == "fold", "Weak hand calls a huge bet")
  end
end
uno = GameRoomGames::Uno.new
check.call("UNO: bot delay 1..5 and thinking-time validation") do
  assert(uno.default_options["bot_delay"] == 1, "Missing bot delay option")
  assert(uno.options_error({ "bot_delay" => 6 }), "Delay above 5 allowed")
  assert(uno.options_error({ "bot_delay" => 3, "thinking_time" => 2 }), "Delay longer than thinking time allowed")
  assert(!uno.options_error({ "bot_delay" => 5, "thinking_time" => 0 }), "Unlimited thinking blocks 5 seconds")
  state = initial(uno, "bot_delay" => 5, "thinking_time" => 5)
  state.update(current_player: "Alice", turn_deadline: 1_800_000_005)
  assert(uno.bot_move_delay(view(state), "Alice", context: context_for) == 4, "Delay consumes the whole deadline")
  state[:turn_deadline] = 1_800_000_001
  assert(uno.bot_move_delay(view(state), "Alice", context: context_for) == 0, "One-second turn always times out")
  state[:turn_deadline] = 0
  assert(uno.bot_move_delay(view(state), "Alice", context: context_for) == 5, "Unlimited turn ignores selected delay")
end
puts JSON.pretty_generate(results)
abort "Feedback regressions failed" if results.any? { |r| r[1] == "FAIL" }
