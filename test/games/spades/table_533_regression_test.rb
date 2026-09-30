def _(text)
  text
end

require_relative "../../../games/spades"

def assert(condition, message)
  raise message if !condition
end

ReplayForTable533 = Struct.new(:state, :accepted_events, :players)

def scored_choice(game, state, actor, events: [], seed: 903)
  replay = ReplayForTable533.new(state, events, state[:players])
  strategy = game.bot_strategy
  context = game.bot_decision_context(replay, actor)
  policy = strategy.policy || strategy.policies.for_state(state)
  scored = game.legal_actions(replay, actor).map do |action|
    features = game.bot_action_features(replay, actor, action, context: context)
    shared = game.bot_policy_score_adjustment(state, actor, action, context)
    planned = game.bot_planning_score_adjustment(state, actor, action, context)
    [action, policy.score(state[:phase].to_s, features) + shared + planned]
  end
  best = scored.map(&:last).max
  choice = GameRoomBots.random_choice(
    scored.select { |_action, score| score == best }.map(&:first),
    GameRoomRandom::SeededSource.new(seed)
  )
  [[choice, best], context, scored]
end

game = GameRoomGames::Spades.new
players = ["papierek", "bot:533:1", "bot:533:2"]
options = {
  "score_limit" => 300,
  "team_size" => 0,
  "no_hell" => false,
  "quicksand" => true,
  "suicide" => false,
  "omniscient_bots" => true
}

# Table 533, round 5: Computer 2 declared nil even though the exact hand
# estimator proved that AD was a cashable control. A sampled cooperative line
# must not make an impossible nil competitive.
nil_state = {
  players: players,
  options: options.dup,
  units: players,
  scores: { "papierek" => 110, "bot:533:1" => 190, "bot:533:2" => 230 },
  round: 5,
  dealer_index: 1,
  bids: {},
  tricks: players.each_with_object({}) { |player, result| result[player] = 0 },
  hands: {
    "papierek" => %w[8H TS 7D QH 6C 7C TC 2H 8S QS 4S AH 8C 9S JD KS KH],
    "bot:533:1" => %w[KD TD 6D 2S 8D 5H 6S 9D JH 5D JS QC 5S 3D TH AC AS],
    "bot:533:2" => %w[5C 3S 7H 3H 3C 4H KC 9C 2D AD QD 6H JC 7S 4D 4C 9H]
  },
  current_trick: [],
  current_player: "bot:533:2",
  spades_broken: false,
  phase: :bidding,
  winner: nil
}
assert(game.send(:estimated_certain_tricks, nil_state, "bot:533:2") >= 1,
  "the exact estimator no longer recognizes the certain trick in round 5")
nil_result, = scored_choice(game, nil_state, "bot:533:2")
assert(nil_result.first["bid"].to_i != 0,
  "the bot still declares nil with a mathematically certain trick")

# Table 533, round 6: Computer 2 intentionally bid one to attack Computer 1's
# nil and prevent an immediate match win. This aggressive line was accepted by
# the user and must not be removed by the nil guard above.
sacrifice_state = {
  players: players,
  options: options.dup,
  units: players,
  scores: { "papierek" => 150, "bot:533:1" => 260, "bot:533:2" => 130 },
  round: 6,
  dealer_index: 2,
  bids: { "papierek" => 8, "bot:533:1" => 0 },
  tricks: players.each_with_object({}) { |player, result| result[player] = 0 },
  hands: {
    "papierek" => %w[3H TC JC KD KS AS JS 3D QH 5D KH 4C 7S QS 4S 7C JD],
    "bot:533:1" => %w[4H 8D 7D 5H JH 3S 9C 9H 3C 2S AC QC 6H 5C 2D QD 2H],
    "bot:533:2" => %w[9S KC 8C TS 6S 6C 8H 8S AH 5S 7H 6D AD TD 4D TH 9D]
  },
  current_trick: [],
  current_player: "bot:533:2",
  spades_broken: false,
  phase: :bidding,
  winner: nil
}
sacrifice_result, = scored_choice(game, sacrifice_state, "bot:533:2")
sacrifice_bid = sacrifice_result.first["bid"].to_i
assert(sacrifice_bid.between?(1, 2),
  "the accepted low nil-breaking declaration changed to #{sacrifice_bid}")

# Table 533, round 8 after Computer 2 won the first two tricks. Papierek needs
# exactly seven to cross 300. Computer 2 has already made its bid of two, but
# must cash a guaranteed winner instead of leading TD and allowing QD to move
# the opponent one trick closer to winning the match.
def without_cards(cards, removed)
  cards.reject { |card| removed.include?(card) }
end

def play_event(actor, card)
  { "action" => "play", "actor" => actor, "value" => card }
end

defense_state = {
  players: players,
  options: options.dup,
  units: players,
  scores: { "papierek" => 250, "bot:533:1" => 220, "bot:533:2" => 80 },
  round: 8,
  dealer_index: 1,
  bids: { "bot:533:2" => 2, "papierek" => 7, "bot:533:1" => 4 },
  tricks: { "papierek" => 0, "bot:533:1" => 0, "bot:533:2" => 2 },
  hands: {
    "papierek" => without_cards(%w[5S 5H 4H QH 8S 2H AS 9C QD 5C 9S KS 3D 9H 3H AC 9D], %w[9C 9D]),
    "bot:533:1" => without_cards(%w[JH 3S 7D 6D 8C 2S 4D QS 8D 4S 7S QC JC TH JS JD TC], %w[8C 4D]),
    "bot:533:2" => without_cards(%w[6S 5D AD 6H KH 3C 7C 2D 8H KD 6C AH TS KC TD 4C 7H], %w[KC KD])
  },
  current_trick: [],
  current_player: "bot:533:2",
  spades_broken: false,
  phase: :playing,
  winner: nil
}
defense_events = [
  { "action" => "deal" },
  play_event("bot:533:2", "KC"), play_event("papierek", "9C"), play_event("bot:533:1", "8C"),
  play_event("bot:533:2", "KD"), play_event("papierek", "9D"), play_event("bot:533:1", "4D")
]
defense_result, defense_context, defense_scores = scored_choice(
  game, defense_state, "bot:533:2", events: defense_events
)
defense_card = defense_result.first["card"]
assert(defense_context[:win_probabilities].fetch(defense_card, 0.0) >= 1.0,
  "match defence still leads #{defense_card}, which does not guarantee the trick")
assert(defense_scores.any? { |entry| entry.first["card"] == "AD" },
  "the reconstructed round no longer contains AD as a legal defence")

puts "Spades table 533 regressions passed"
