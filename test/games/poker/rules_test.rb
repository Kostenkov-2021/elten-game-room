require_relative '../../support/new_games_fixture'

players = %w[Alice Bob Carol]
repository = NewGames116Repository.new(players)

poker = GameRoomGames::Poker.new
poker_definitions = poker.option_definitions.to_h { |definition| [definition.key, definition] }
assert(!poker.option_visible?(poker_definitions["raise_cap"], poker.default_options),
  "Poker shows the disabled raise limit")
assert(poker.option_visible?(poker_definitions["raise_cap"], poker.default_options.merge("raise_cap_enabled" => true)),
  "Poker hides the enabled raise limit")
draw_options = poker.default_options.merge("variant" => "draw", "draw_uses_blinds" => false)
assert(poker.option_visible?(poker_definitions["ante"], draw_options) &&
  !poker.option_visible?(poker_definitions["small_blind"], draw_options),
  "Draw poker does not switch from blinds to the ante fields")
assert(poker.validation_error(draw_options.merge("small_blind" => 0), player_count: 3) == nil,
  "Poker validates a hidden blind field")
assert(poker.validation_error(draw_options.merge("ante" => 0), player_count: 3) != nil,
  "Draw poker accepts an invalid visible ante")
assert(poker.options_summary(draw_options).include?("ante 5") && !poker.options_summary(draw_options).include?("blinds"),
  "Poker draw settings describe hidden blinds instead of the ante")
poker_session = { "options" => JSON.generate(poker.default_options) }
poker_events = []
poker_replay = poker.replay(poker_session, poker_events, repository)
poker_replay = append_action(poker, poker_session, repository, poker_events, poker_replay, "Alice",
  poker.automatic_action(poker_replay, "Alice"), context_for)
assert(poker_replay.state[:hands].values.all? { |hand| hand.length == 2 }, "Hold'em did not deal two private cards")
assert(poker_replay.state[:contributions].values.sum == 15, "Hold'em did not post the default blinds")
poker_actor = poker_replay.current_player
poker_move = poker.legal_actions(poker_replay, poker_actor).find { |action| %w[check call].include?(action["action"]) }
poker_replay = append_action(poker, poker_session, repository, poker_events, poker_replay, poker_actor, poker_move)
assert(poker_replay.accepted_events.length == 2, "Poker rejected its first betting action")
assert(poker.send(:five_card_rank, %w[AS KS QS JS TS]).first == 8, "Poker evaluator missed a royal straight flush")
assert(poker.send(:five_card_rank, %w[AS AD AC AH 2S]).first == 7, "Poker evaluator missed four of a kind")
assert(poker.send(:best_combination_text, %w[2C 2D]) == "one pair: 2.",
  "Poker G does not recognize a pocket pair before the flop")

all_in_state = poker.send(:initial_state, %w[Alice Bob], poker.default_options)
all_in_state.update(
  phase: :betting, current_player: "Alice", dealer_index: 0,
  hands: { "Alice" => %w[2C 2D], "Bob" => %w[3C 4D] },
  stacks: { "Alice" => 100, "Bob" => 90 }, street: 0, current_bet: 10,
  min_raise: 10, street_bets: { "Alice" => 0, "Bob" => 10 },
  contributions: { "Alice" => 0, "Bob" => 10 }, folded: {}, all_in: {}, acted: {}
)
all_in_history = []
assert(poker.send(:apply_bet, all_in_state,
  { "id" => 99, "actor" => "Alice", "action" => "bet", "value" => "all_in|100" },
  "Alice", repository, all_in_history), "Poker rejected a legal all-in")
assert(all_in_state[:phase] == :betting && all_in_state[:current_player] == "Bob",
  "Poker ended the hand immediately instead of letting the opponent answer an all-in")

heads_up_players = %w[Alice Bob]
heads_up_repository = NewGames116Repository.new(heads_up_players)
heads_up_state = poker.send(:initial_state, heads_up_players, poker.default_options)
heads_up_history = []
assert(poker.send(:apply_deal, heads_up_state,
  { "id" => 100, "actor" => "Alice", "action" => "deal", "value" => "1|0|0123456789abcdef0123456789abcdef|1800000000" },
  "Alice", heads_up_repository, heads_up_history), "Heads-up Hold'em deal failed")
assert(heads_up_state[:street_bets]["Alice"] == 5 && heads_up_state[:street_bets]["Bob"] == 10 &&
  heads_up_state[:current_player] == "Alice",
  "Heads-up Hold'em did not place the dealer in the small blind with first pre-flop action")

jacks_options = poker.normalize_options("variant" => "draw", "jacks_or_better" => true)
jacks_state = poker.send(:initial_state, players, jacks_options)
jacks_state.update(phase: :betting, current_player: "Alice", street: 0,
  hands: { "Alice" => %w[2C 4D 6H 8S TC], "Bob" => %w[3C 5D 7H 9S JC], "Carol" => %w[3D 5H 7S 9C QD] })
jacks_replay = GameRoomGames::Replay.new(players: players, current_player: "Alice", winner: nil,
  draw: false, accepted_events: [], history: [], state: jacks_state)
assert(poker.legal_actions(jacks_replay, "Alice").none? { |action| %w[raise all_in].include?(action["action"]) },
  "Jacks-or-better allowed an unqualified player to open")
jacks_state[:hands]["Alice"] = %w[JC JD 6H 8S TC]
assert(poker.legal_actions(jacks_replay, "Alice").any? { |action| action["action"] == "raise" },
  "Jacks-or-better rejected a pair of jacks as an opening hand")

first_shuffle = poker.send(:shuffled_cards, (1..52).to_a, "0123456789abcdef0123456789abcdef")
second_shuffle = poker.send(:shuffled_cards, (1..52).to_a, "0123456789abcdef0123456789abcdef")
assert(first_shuffle == second_shuffle && first_shuffle.sort == (1..52).to_a,
  "the portable card shuffle is not deterministic or lost cards")

puts 'PASS poker: rules, legal actions and options'
