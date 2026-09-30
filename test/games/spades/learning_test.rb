require_relative "../../../tools/training/spades_training"
def _(text)
  text
end

require_relative "../../../lib/spades_learning"
require_relative "../../../games/spades"

def assert(condition, message)
  raise message if !condition
end

game = GameRoomGames::Spades.new
players = GameRoomParticipants.bots_for(1, 4)
environment = GameRoomSimulation::Environment.new_game(
  game: game,
  players: players,
  options: { "score_limit" => 30, "team_size" => 2 },
  seed: 71
)
while environment.replay.state[:phase] == :bidding
  actor = environment.active_actor
  action = environment.legal_actions(actor).find { |candidate| candidate["bid"] == 1 }
  action ||= environment.legal_actions(actor).first
  assert(environment.step(action, actor: actor) == :ok, "training setup rejected a legal bid")
end

actor = environment.active_actor
action = environment.legal_actions(actor).first
features = game.bot_action_features(environment.replay, actor, action)
assert(features.key?("low_card"), "Spades did not expose playing features")
assert(features.key?("last_win_needed"), "Spades learning cannot reason about its contract")
assert(features.key?("cheapest_winner"), "Spades learning cannot conserve winning cards")
assert(features.key?("unneeded_win_probability"), "Spades learning cannot avoid likely overtricks")
assert(features.key?("unneeded_high_release"), "Spades learning cannot safely shed high cards")
assert(features.key?("opponent_nil_pressure"), "Spades learning cannot attack nil")
assert(features.key?("quicksand_extra_win"), "Spades learning cannot distinguish Quicksand overtricks")

decision_context = game.bot_decision_context(environment.replay, actor)
assert(!decision_context.key?(:hands), "the bot decision context exposes private hands")
assert(
  (decision_context[:unseen_cards] & environment.replay.state[:hands][actor]).empty?,
  "the bot counted its own hand as unseen"
)

changed = Marshal.load(Marshal.dump(environment.replay))
opponents = changed.players.reject { |player| GameRoomParticipants.same?(player, actor) }
first_hand = changed.state[:hands][opponents[0]]
changed.state[:hands][opponents[0]] = changed.state[:hands][opponents[1]]
changed.state[:hands][opponents[1]] = first_hand
assert(
  game.bot_action_features(changed, actor, action) == features,
  "Spades learning features reveal an opponent's private hand"
)

omniscient_state = {
  players: %w[B A C],
  options: {
    "score_limit" => 300,
    "team_size" => 0,
    "quicksand" => false,
    "omniscient_bots" => true
  },
  scores: { "B" => 0, "A" => 0, "C" => 0 },
  bids: { "B" => 1, "A" => 1, "C" => 1 },
  tricks: { "B" => 0, "A" => 0, "C" => 0 },
  hands: { "B" => %w[2C], "A" => %w[TH], "C" => %w[AH] },
  current_trick: [{ player: "B", card: "9H" }],
  current_player: "A",
  spades_broken: false,
  phase: :playing
}
omniscient_replay_class = Struct.new(:state, :accepted_events, :players)
omniscient_replay = omniscient_replay_class.new(
  omniscient_state,
  [],
  omniscient_state[:players]
)
omniscient_context = game.bot_decision_context(omniscient_replay, "A")
assert(omniscient_context[:omniscient] == true,
  "the explicit omniscient option did not enable the private decision context")
assert(omniscient_context[:known_hands]["C"] == %w[AH],
  "the omniscient bot cannot inspect an opponent's remaining hand")
assert(omniscient_context[:win_probabilities]["TH"] == 0.0,
  "the omniscient bot ignores a known higher reply")

omniscient_changed = Marshal.load(Marshal.dump(omniscient_state))
omniscient_changed[:hands]["B"] = %w[AH]
omniscient_changed[:hands]["C"] = %w[2H]
changed_context = game.bot_decision_context(
  omniscient_replay_class.new(omniscient_changed, [], omniscient_changed[:players]),
  "A"
)
assert(changed_context[:win_probabilities]["TH"] == 1.0,
  "the omniscient bot did not react to the actual location of private cards")
assert(
  !game.bot_observation(omniscient_replay, "A").key?("hands"),
  "the omniscient challenge leaked private hands through the public observation"
)

policy = SpadesLearning::Policy.default
restored = SpadesLearning::Policy.from_json(policy.to_json)
assert(restored.weights == policy.weights, "serialized Spades weights changed")
mutation = policy.mutated(Random.new(4), scale: 0.5)
assert(mutation.weights != policy.weights, "Spades policy mutation changed no weights")

policy_set = SpadesLearning::PolicySet.strategic
assert(
  policy_set.for_options("quicksand" => false, "team_size" => 0) !=
    policy_set.for_options("quicksand" => true, "team_size" => 0),
  "Standard and Quicksand use the same policy object"
)
assert(
  SpadesLearning::PolicySet.profile_key("quicksand" => true, "team_size" => 3) == "quicksand_team",
  "the Quicksand team profile was selected incorrectly"
)

default_policy_set = SpadesLearning::PolicySet.default
build_48_weights = SpadesLearning::Policy::BUILD_48_WEIGHTS
assert(
  SpadesLearning::PolicySet.build_48.for_options("quicksand" => false, "team_size" => 0).weights == build_48_weights,
  "the immutable build 48 reference was changed"
)
%w[standard_individual_p3 standard_individual_p4 quicksand_team_p4_t2].each do |profile|
  base = SpadesLearning::PolicySet.base_profile_key(profile)
  complete = SpadesLearning::Policy.strategic(base).weights
  actual = default_policy_set.profiles.fetch(profile).weights
  complete.each do |phase, entries|
    missing = entries.keys - actual.fetch(phase).keys
    assert(missing.empty?, "#{profile} silently disabled strategic features: #{missing.join(', ')}")
  end
end
assert(
  SpadesLearning::Policy::INDIVIDUAL_INACTIVE_FEATURES.all? do |feature|
    default_policy_set.profiles.fetch("standard_individual_p3").weights["playing"][feature] == 0.0
  end,
  "an individual profile retained strategies that require a partner"
)
standard_team_p4 = default_policy_set.profiles.fetch("standard_team_p4_t2").weights
assert(
  standard_team_p4["bidding"]["distance"] == default_policy_set.profiles.fetch("standard_team").weights["bidding"]["distance"] &&
    standard_team_p4["bidding"]["table_bid_balance"] > 0.0,
  "an arrangement override did not inherit its trained broad profile"
)
assert(
  default_policy_set.for_state(
    options: { "quicksand" => false, "team_size" => 0 },
    players: GameRoomParticipants.bots_for(800, 5)
  ).weights["bidding"]["table_bid_balance"] == 0.0,
  "an unvalidated arrangement enabled table bid balancing"
)
assert(
  default_policy_set.for_state(
    options: { "quicksand" => false, "team_size" => 0 },
    players: GameRoomParticipants.bots_for(2, 5)
  ).weights == default_policy_set.profiles.fetch("standard_individual").weights,
  "an arrangement without an override did not use its broad trained profile"
)
assert(
  default_policy_set.for_state(
    options: { "quicksand" => true, "team_size" => 2 },
    players: GameRoomParticipants.bots_for(3, 4)
  ).weights == default_policy_set.profiles.fetch("quicksand_team_p4_t2").weights,
  "the arrangement-specific Quicksand profile was not selected"
)
quicksand_team_p6_t2 = default_policy_set.for_state(
  options: { "quicksand" => true, "team_size" => 2 },
  players: GameRoomParticipants.bots_for(3, 6)
).weights
assert(
  quicksand_team_p6_t2 == default_policy_set.profiles.fetch("quicksand_team_p6_t2").weights &&
    quicksand_team_p6_t2["bidding"]["team_bid_balance"] == 2.8830409383820346 &&
    quicksand_team_p6_t2["playing"]["quicksand_extra_win"] == -11.719753790008976,
  "the independently validated six-player Quicksand team profile was not selected"
)

three_player_environment = GameRoomSimulation::Environment.new_game(
  game: game,
  players: GameRoomParticipants.bots_for(200, 3),
  options: { "score_limit" => 30, "team_size" => 0 },
  seed: 901
)
2.times do
  bidder = three_player_environment.active_actor
  action = three_player_environment.legal_actions(bidder).find { |candidate| candidate["bid"] == 1 }
  assert(three_player_environment.step(action, actor: bidder) == :ok, "the table-balance setup rejected a bid")
end
last_bidder = three_player_environment.active_actor
low_bid = three_player_environment.legal_actions(last_bidder).find { |candidate| candidate["bid"] == 1 }
high_bid = three_player_environment.legal_actions(last_bidder).find { |candidate| candidate["bid"] == 8 }
low_features = game.bot_action_features(three_player_environment.replay, last_bidder, low_bid)
high_features = game.bot_action_features(three_player_environment.replay, last_bidder, high_bid)
assert(low_features["last_bid_table_balance"] < high_features["last_bid_table_balance"],
  "the final bidder cannot softly account for unallocated tricks")

probability_state = {
  players: %w[A B C],
  options: { "score_limit" => 300, "team_size" => 0, "quicksand" => false },
  scores: { "A" => 0, "B" => 0, "C" => 0 },
  bids: { "A" => 1, "B" => 1, "C" => 1 },
  tricks: { "A" => 1, "B" => 0, "C" => 0 },
  hands: {
    "A" => %w[2H TH AH 2C 3C 4C 5C 6C 7C 8C 9C TC JC QC KC AC 2D],
    "B" => [],
    "C" => []
  },
  current_trick: [],
  current_player: "A",
  spades_broken: false,
  phase: :playing
}
probability_context = {
  unseen_cards: game.send(:deck_for, 3) - probability_state[:hands]["A"],
  void_suits: {},
  cheapest_winner: "2H",
  highest_loser: nil,
  score: { deficit: 0.0, bags: 0 }
}
low_release = game.send(:playing_bot_features,
  Struct.new(:state).new(probability_state), "A", { "card" => "2H" }, probability_context)
high_release = game.send(:playing_bot_features,
  Struct.new(:state).new(probability_state), "A", { "card" => "TH" }, probability_context)
ace_risk = game.send(:playing_bot_features,
  Struct.new(:state).new(probability_state), "A", { "card" => "AH" }, probability_context)
assert(low_release["cheapest_winner"] == 0.0,
  "a completed contract still rewards the cheapest provisional winner")
assert(high_release["unneeded_high_release"] > low_release["unneeded_high_release"],
  "the bot does not prefer shedding a high card that is likely to be overtaken")
assert(ace_risk["unneeded_win_probability"] > high_release["unneeded_win_probability"],
  "the bot cannot distinguish a certain overtrick from a likely losing lead")
p3_policy = default_policy_set.for_state(probability_state)
assert(p3_policy.score("playing", high_release) > p3_policy.score("playing", low_release),
  "the standard three-player bot keeps a dangerous high card instead of shedding it safely: " \
    "low=#{p3_policy.score('playing', low_release)}, high=#{p3_policy.score('playing', high_release)}")
assert(p3_policy.score("playing", high_release) > p3_policy.score("playing", ace_risk),
  "the standard three-player bot prefers a certain overtrick to a likely losing card")

# Regression for a real three-player round: after both opponents showed that
# they were void in hearts, a bot that still needed six tricks repeatedly led
# hearts and treated them as certain winners. It must account for a possible
# ruff and draw trump instead.
void_lead_state = {
  players: %w[A B C],
  options: { "score_limit" => 300, "team_size" => 0, "quicksand" => false },
  scores: { "A" => -60, "B" => 86, "C" => -49 },
  bids: { "A" => 11, "B" => 3, "C" => 1 },
  tricks: { "A" => 5, "B" => 5, "C" => 1 },
  hands: {
    "A" => %w[AH AS QS KS TH 9H],
    "B" => [],
    "C" => []
  },
  current_trick: [],
  current_player: "A",
  spades_broken: true,
  phase: :playing
}
void_lead_context = {
  unseen_cards: %w[2S 3S 4S 2C 3C 4C 5C 6C 2D 3D 4D 5D],
  void_suits: { "B" => ["H"], "C" => ["H"] },
  cheapest_winner: "9H",
  highest_loser: nil,
  score: { deficit: 0.0, bags: 0 }
}
ruffed_heart = game.send(:playing_bot_features,
  Struct.new(:state).new(void_lead_state), "A", { "card" => "9H" }, void_lead_context)
trump_draw = game.send(:playing_bot_features,
  Struct.new(:state).new(void_lead_state), "A", { "card" => "QS" }, void_lead_context)
safe_heart = game.send(:playing_bot_features,
  Struct.new(:state).new(void_lead_state), "A", { "card" => "9H" },
  void_lead_context.merge(void_suits: {}))
assert(ruffed_heart["needed_win_probability"] == 0.0,
  "the bot still treats a side suit as safe when every opponent can ruff")
assert(ruffed_heart["known_winner_needed"] == 0.0,
  "a ruffable side-suit card is still marked as a known winner")
assert(safe_heart["needed_win_probability"] > 0.99,
  "the ruff correction also penalizes an unbeaten suit with no known void")
assert(p3_policy.score("playing", trump_draw) > p3_policy.score("playing", ruffed_heart),
  "the bot leads a known ruffable heart instead of drawing trump while its contract is endangered")

# Card counting can prove a void before anybody has visibly failed to follow.
# In the observed round all twelve other hearts had already been played and the
# bot held the thirteenth, so both opponents were certainly able to ruff it.
exhausted_hearts_state = {
  players: ["papierek", "bot:62:1", "bot:62:2"],
  options: { "score_limit" => 300, "team_size" => 0, "quicksand" => false },
  scores: { "papierek" => 0, "bot:62:1" => 0, "bot:62:2" => 0 },
  bids: { "papierek" => 3, "bot:62:1" => 7, "bot:62:2" => 8 },
  tricks: { "papierek" => 1, "bot:62:1" => 1, "bot:62:2" => 4 },
  hands: {
    "papierek" => [],
    "bot:62:1" => [],
    "bot:62:2" => %w[2S 4C 4S 7C 7D 8C 8S 9C 9H JS QS]
  },
  current_trick: [],
  current_player: "bot:62:2",
  spades_broken: false,
  phase: :playing
}
exhausted_hearts_events = [
  ["papierek", "TD"], ["bot:62:1", "QD"], ["bot:62:2", "KD"],
  ["bot:62:2", "4H"], ["papierek", "6H"], ["bot:62:1", "7H"],
  ["bot:62:1", "2H"], ["bot:62:2", "8H"], ["papierek", "QH"],
  ["papierek", "TC"], ["bot:62:1", "QC"], ["bot:62:2", "AC"],
  ["bot:62:2", "KH"], ["papierek", "5H"], ["bot:62:1", "TH"],
  ["bot:62:2", "AH"], ["papierek", "3H"], ["bot:62:1", "JH"]
].map { |player, card| { "action" => "play", "actor" => player, "value" => card } }
exhausted_hearts_events.unshift({ "action" => "deal", "actor" => "papierek", "value" => "test" })
exhausted_hearts_replay = Struct.new(:state, :accepted_events, :players).new(
  exhausted_hearts_state,
  exhausted_hearts_events,
  exhausted_hearts_state[:players]
)
exhausted_hearts_context = game.bot_decision_context(exhausted_hearts_replay, "bot:62:2")
assert(exhausted_hearts_context[:void_suits]["papierek"].include?("H") &&
  exhausted_hearts_context[:void_suits]["bot:62:1"].include?("H"),
  "the bot cannot infer an exhausted suit from its hand and the public play log")
exhausted_heart = game.bot_action_features(
  exhausted_hearts_replay, "bot:62:2", { "card" => "9H" }, context: exhausted_hearts_context
)
assert(exhausted_heart["needed_win_probability"] == 0.0 &&
  exhausted_heart["known_winner_needed"] == 0.0,
  "the last card of an exhausted side suit is still treated as a certain winner")

early_avoidance_state = Marshal.load(Marshal.dump(probability_state))
early_avoidance_state[:bids]["A"] = 4
early_avoidance_state[:tricks]["A"] = 3
early_plan = game.send(:bot_contract_plan, early_avoidance_state, "A")
assert(early_plan[:avoidance_pressure] > 0.0,
  "the bot cannot start shedding tricks before a safely covered contract is formally complete")
assert(early_plan[:completed_avoidance_pressure] == 0.0 && early_plan[:early_avoidance_pressure] > 0.0,
  "early trick avoidance is not separated from the stronger post-contract policy")
early_context = probability_context.merge(
  unseen_cards: game.send(:deck_for, 3) - early_avoidance_state[:hands]["A"]
)
early_risky_winner = game.send(:playing_bot_features,
  Struct.new(:state).new(early_avoidance_state), "A", { "card" => "AH" }, early_context)
early_safe_release = game.send(:playing_bot_features,
  Struct.new(:state).new(early_avoidance_state), "A", { "card" => "TH" }, early_context)
assert(early_risky_winner["unneeded_win_probability"] == 0.0 &&
  early_risky_winner["early_avoid_win_probability"] > 0.0,
  "pre-contract avoidance incorrectly uses the fully completed-contract behavior")
assert(p3_policy.score("playing", early_safe_release) >
  p3_policy.score("playing", early_risky_winner),
  "the bot accepts a likely forced extra trick before its safely covered contract is complete")
urgent_state = Marshal.load(Marshal.dump(probability_state))
urgent_state[:bids]["A"] = 10
urgent_state[:tricks]["A"] = 0
urgent_plan = game.send(:bot_contract_plan, urgent_state, "A")
assert(urgent_plan[:contract_pressure] > urgent_plan[:avoidance_pressure],
  "the bot sheds tricks while its contract is still in danger")

one_spare_pressure = game.send(:bot_overtrick_avoidance_pressure, probability_state, "A", 1.0)
two_spare_pressure = game.send(:bot_overtrick_avoidance_pressure, probability_state, "A", 2.0)
assert(one_spare_pressure == 0.0 && two_spare_pressure > 0.0,
  "the bot treats one accidental overtrick as severely as several overtricks")
high_bag_state = Marshal.load(Marshal.dump(probability_state))
high_bag_state[:scores]["A"] = 8
high_bag_pressure = game.send(:bot_overtrick_avoidance_pressure, high_bag_state, "A", 1.0)
assert(high_bag_pressure > one_spare_pressure,
  "accumulated bags do not make the bot more cautious about another overtrick")
quicksand_overtrick_state = Marshal.load(Marshal.dump(probability_state))
quicksand_overtrick_state[:options]["quicksand"] = true
assert(game.send(:bot_overtrick_avoidance_pressure, quicksand_overtrick_state, "A", 1.0) == 1.0,
  "Quicksand tolerates an overtrick as if it had no immediate point cost")

# Regression for the next observed round. The bot needed two tricks and held
# A-K-Q-J of clubs, but early avoidance made it lead the three. After the two
# opponents exhausted their clubs, the remaining honors were ruffed and the
# four-trick contract failed. Cash the cheapest card of a reliable run until
# the contract is secured, without disabling early avoidance for isolated
# winners tested above.
contract_run_actor = "bot:62:2"
contract_run_state = {
  players: ["papierek", "bot:62:1", contract_run_actor],
  options: { "score_limit" => 300, "team_size" => 0, "quicksand" => false },
  scores: { "papierek" => 31, "bot:62:1" => 122, contract_run_actor => -40 },
  bids: { contract_run_actor => 4, "papierek" => 5, "bot:62:1" => 7 },
  tricks: { "papierek" => 3, "bot:62:1" => 3, contract_run_actor => 2 },
  hands: {
    "papierek" => [],
    "bot:62:1" => [],
    contract_run_actor => %w[KC AC 8H JH 4C QC 5C 3C JC]
  },
  current_trick: [],
  current_player: contract_run_actor,
  spades_broken: true,
  phase: :playing
}
contract_run_events = [
  [contract_run_actor, "3H"], ["papierek", "9H"], ["bot:62:1", "KH"],
  ["bot:62:1", "2D"], [contract_run_actor, "8D"], ["papierek", "9D"],
  ["papierek", "AD"], ["bot:62:1", "3D"], [contract_run_actor, "4S"],
  [contract_run_actor, "4H"], ["papierek", "TH"], ["bot:62:1", "AH"],
  ["bot:62:1", "2S"], [contract_run_actor, "6S"], ["papierek", "8S"],
  ["papierek", "QH"], ["bot:62:1", "7H"], [contract_run_actor, "5H"],
  ["papierek", "2H"], ["bot:62:1", "7S"], [contract_run_actor, "6H"],
  ["bot:62:1", "4D"], [contract_run_actor, "TS"], ["papierek", "JD"]
].map { |player, card| { "action" => "play", "actor" => player, "value" => card } }
contract_run_events.unshift({ "action" => "deal", "actor" => "papierek", "value" => "test" })
contract_run_replay = Struct.new(:state, :accepted_events, :players).new(
  contract_run_state,
  contract_run_events,
  contract_run_state[:players]
)
contract_run_context = game.bot_decision_context(contract_run_replay, contract_run_actor)
assert(contract_run_context[:cash_contract_run] == "JC",
  "the bot did not identify the cheapest card in a contract-winning honor run")
contract_run_policy = default_policy_set.for_state(contract_run_state)
contract_run_scores = game.legal_actions(contract_run_replay, contract_run_actor).to_h do |candidate|
  candidate_features = game.bot_action_features(
    contract_run_replay, contract_run_actor, candidate, context: contract_run_context
  )
  [candidate["card"], contract_run_policy.score("playing", candidate_features)]
end
assert(contract_run_scores.max_by { |_card, score| score }.first == "JC",
  "the bot still ducks a certain contract run with a low club")
low_contract_lead = game.bot_action_features(
  contract_run_replay, contract_run_actor, { "card" => "3C" }, context: contract_run_context
)
assert(low_contract_lead["win_before_last"] == 0.0 &&
  low_contract_lead["trailing_contract_win"] == 0.0,
  "a zero-probability lead still receives credit for winning a contract trick")

next_contract_run_state = Marshal.load(Marshal.dump(contract_run_state))
next_contract_run_state[:hands][contract_run_actor].delete("JC")
next_contract_run_state[:tricks][contract_run_actor] = 3
next_contract_run_events = contract_run_events + [
  { "action" => "play", "actor" => contract_run_actor, "value" => "JC" },
  { "action" => "play", "actor" => "papierek", "value" => "TC" },
  { "action" => "play", "actor" => "bot:62:1", "value" => "7C" }
]
next_contract_run_replay = Struct.new(:state, :accepted_events, :players).new(
  next_contract_run_state,
  next_contract_run_events,
  next_contract_run_state[:players]
)
next_contract_run_context = game.bot_decision_context(next_contract_run_replay, contract_run_actor)
assert(next_contract_run_context[:cash_contract_run] == "QC",
  "the bot stops cashing a reliable run one trick before making its contract")

six_player_plan_state = Marshal.load(Marshal.dump(probability_state))
six_player_plan_state[:players] = %w[A B C D E F]
six_player_plan_state[:options]["quicksand"] = true
six_player_plan_state[:scores] = six_player_plan_state[:players].to_h { |player| [player, 0] }
six_player_plan_state[:bids] = six_player_plan_state[:players].to_h { |player| [player, 1] }
six_player_plan_state[:tricks] = six_player_plan_state[:players].to_h { |player| [player, 0] }
six_player_plan_state[:hands] = six_player_plan_state[:players].to_h { |player| [player, []] }
six_player_plan_state[:hands]["A"] = %w[AS AH 2H 3C 4C 5D 6D 7D]
fragile_short_hand_plan = game.send(:bot_contract_plan, six_player_plan_state, "A")
assert(fragile_short_hand_plan[:early_avoidance_pressure] == 0.0,
  "a six-player bot ducks on the strength of only one projected spare trick")
six_player_plan_state[:hands]["A"] = %w[AS AH AD 3C 4C 5D 6D 7D]
safe_short_hand_plan = game.send(:bot_contract_plan, six_player_plan_state, "A")
assert(safe_short_hand_plan[:early_avoidance_pressure] > 0.0,
  "a six-player bot cannot duck before bidding despite two secure spare tricks")

short_hand_state = Marshal.load(Marshal.dump(probability_state))
short_hand_state[:hands]["A"] = %w[AS KS QS 2S 3S 2H 2D 3D 4D 5D 6D 2C 3C 4C 5C 6C 7C]
balanced_hand_state = Marshal.load(Marshal.dump(probability_state))
balanced_hand_state[:hands]["A"] = %w[AS KS QS 2S 3S 2H 3H 4H 5H 2D 3D 4D 5D 2C 3C 4C 5C]
assert(game.send(:estimated_bot_bid, short_hand_state, "A") >
  game.send(:estimated_bot_bid, balanced_hand_state, "A"),
  "the bid estimator ignores singleton and doubleton ruff opportunities")
assert(!game.send(:deck_for, 3).include?("2C") && game.send(:deck_for, 3).include?("2D"),
  "the three-player estimator uses the wrong shortened suit")

# Regression for a real three-player hand. Its raw mean was 5.93 tricks, but
# with only two spades the long diamond and heart honors were both exposed to
# a deliberate ruff attack. The bot bid six and made only three. Preserve the
# calibrated mean used during play, while making the contract target one trick
# safer for this precise hand shape.
fragile_bid_state = {
  players: ["papierek", "bot:59:1", "bot:59:2"],
  options: { "score_limit" => 300, "team_size" => 0, "quicksand" => false },
  scores: { "papierek" => 42, "bot:59:1" => 80, "bot:59:2" => -40 },
  bids: { "bot:59:1" => 5 },
  tricks: {},
  hands: {
    "papierek" => [],
    "bot:59:1" => [],
    "bot:59:2" => %w[TD 4C 8S AD 7D QH 9C JD JH TC KH AS 5H KD TH 4H 6C]
  },
  current_player: "bot:59:2",
  phase: :bidding
}
fragile_actor = "bot:59:2"
fragile_mean = game.send(:estimated_bot_bid, fragile_bid_state, fragile_actor)
fragile_reserve = game.send(:estimated_contract_safety_reserve, fragile_bid_state, fragile_actor)
assert((fragile_mean - 5.93112).abs < 0.0001,
  "the calibrated mean for the observed fragile hand unexpectedly changed")
assert(fragile_reserve == 1.0,
  "the three-player bid target did not reserve a trick for two exposed long suits")
fragile_policy = default_policy_set.for_state(fragile_bid_state)
bid_five = game.send(:bidding_bot_features, fragile_bid_state, fragile_actor, { "bid" => 5 })
bid_six = game.send(:bidding_bot_features, fragile_bid_state, fragile_actor, { "bid" => 6 })
assert(fragile_policy.score("bidding", bid_five) > fragile_policy.score("bidding", bid_six),
  "the observed fragile hand still prefers a six-trick contract over five")

protected_bid_state = Marshal.load(Marshal.dump(fragile_bid_state))
protected_bid_state[:hands][fragile_actor] = %w[TS 2S 6C 9S KS 8H 5D 8S 5H QD 9C 6H AS AD QS TC 4C]
assert(game.send(:estimated_contract_safety_reserve, protected_bid_state, fragile_actor) == 0.0,
  "a trump-rich hand was made needlessly conservative")

# The contested-trick allowance is shared game reasoning, not a collection of
# independently tuned policy weights. It therefore has to cover every player
# arrangement and Quicksand as well as standard scoring. Quicksand still keeps
# its separate card-play penalties for taking an unnecessary extra trick.
shared_target_cases = [
  [%w[A B C], { "score_limit" => 300, "team_size" => 0, "quicksand" => false }, 16.0],
  [%w[A B C D], { "score_limit" => 300, "team_size" => 0, "quicksand" => false }, 12.0],
  [%w[A B C D E F], { "score_limit" => 300, "team_size" => 2, "quicksand" => false }, 7.0],
  [%w[A B C], { "score_limit" => 300, "team_size" => 0, "quicksand" => true }, 16.0],
  [%w[A B C D E F], { "score_limit" => 300, "team_size" => 3, "quicksand" => true }, 7.0]
]
shared_target_cases.each do |target_players, target_options, expected|
  target_state = {
    players: target_players,
    options: target_options,
    scores: {},
    bids: {}
  }
  actual = game.send(:bot_table_bid_target, target_state, target_players.first)
  assert(actual == expected,
    "the shared table target for #{target_players.length} players and " \
      "#{target_options['quicksand'] ? 'Quicksand' : 'standard'} was #{actual}, expected #{expected}")
end

bag_pressure_state = {
  players: %w[A B C],
  options: { "score_limit" => 300, "team_size" => 0, "quicksand" => false },
  scores: { "A" => 9, "B" => 0, "C" => 0 },
  bids: {}
}
assert(game.send(:bot_table_bid_target, bag_pressure_state, "A") == 17.0,
  "a standard player on nine bags cannot deliberately restore the full table target")
quicksand_pressure_state = Marshal.load(Marshal.dump(bag_pressure_state))
quicksand_pressure_state[:options]["quicksand"] = true
assert(game.send(:bot_table_bid_target, quicksand_pressure_state, "A") == 16.0,
  "Quicksand incorrectly inherited the standard ten-bag exception")
catch_up_state = Marshal.load(Marshal.dump(bag_pressure_state))
catch_up_state[:scores] = { "A" => 0, "B" => 150, "C" => 0 }
assert(game.send(:bot_table_bid_target, catch_up_state, "A") == 16.0,
  "match-position aggression silently erased the shared table margin")

loaded_table_state = Marshal.load(Marshal.dump(catch_up_state))
loaded_table_state[:scores] = { "A" => 0, "B" => 0, "C" => 0 }
loaded_table_state[:bids] = { "B" => 5, "C" => 6 }
loaded_table_state[:phase] = :bidding
assert(game.bot_policy_score_adjustment(loaded_table_state, "A", { "bid" => 5 }) == 0.0,
  "a declaration that preserves the shared margin was penalized")
assert(game.bot_policy_score_adjustment(loaded_table_state, "A", { "bid" => 6 }) == -0.85,
  "a declaration that allocates every trick has no shared tactical cost")

# Two declarations reconstructed from the user's real match. The private hand
# estimates were close to the final trick counts, but bidding every remaining
# trick let a human deliberately break a bot's contract. The shared rule must
# change the actual choice, not merely expose another inert feature.
observed_bid_cases = [
  [{
    players: ["papierek", "bot:60:1", "bot:60:2"],
    options: { "score_limit" => 300, "team_size" => 0, "quicksand" => false },
    scores: { "papierek" => 52, "bot:60:1" => -80, "bot:60:2" => 31 },
    bids: { "bot:60:2" => 6, "papierek" => 5 },
    tricks: {},
    hands: {
      "papierek" => [],
      "bot:60:2" => [],
      "bot:60:1" => %w[5C 8C AS AD 3H JH 5H 9S QC AH 9H KH JC 8H 5D 7D TC]
    },
    current_player: "bot:60:1",
    phase: :bidding
  }, "bot:60:1", 5],
  [{
    players: ["papierek", "bot:60:1", "bot:60:2"],
    options: { "score_limit" => 300, "team_size" => 0, "quicksand" => false },
    scores: { "papierek" => 104, "bot:60:1" => -140, "bot:60:2" => 91 },
    bids: { "papierek" => 3, "bot:60:1" => 7 },
    tricks: {},
    hands: {
      "papierek" => [],
      "bot:60:1" => [],
      "bot:60:2" => %w[5D 4C KC 6S 7D KH 4H 3D QH KS 2D 3C 8D 7C AS 8H 9S]
    },
    current_player: "bot:60:2",
    phase: :bidding
  }, "bot:60:2", 6],
  [{
    players: ["papierek", "bot:62:1", "bot:62:2"],
    options: { "score_limit" => 300, "team_size" => 0, "quicksand" => false },
    scores: { "papierek" => 0, "bot:62:1" => 0, "bot:62:2" => 0 },
    bids: { "papierek" => 3, "bot:62:1" => 7 },
    tricks: {},
    hands: {
      "papierek" => [],
      "bot:62:1" => [],
      "bot:62:2" => %w[2S 4C 4H 4S 7C 7D 8C 8H 8S 9C 9H AC AH JS KD KH QS]
    },
    current_player: "bot:62:2",
    phase: :bidding
  }, "bot:62:2", 6]
]
observed_bid_cases.each do |observed_state, observed_actor, expected_bid|
  observed_policy = default_policy_set.for_state(observed_state)
  ranked = (0..game.send(:cards_per_player, observed_state[:players].length)).map do |bid|
    action = { "bid" => bid }
    features = game.send(:bidding_bot_features, observed_state, observed_actor, action)
    score = observed_policy.score("bidding", features) +
      game.bot_policy_score_adjustment(observed_state, observed_actor, action)
    [bid, score]
  end
  actual_bid = ranked.max_by { |_bid, score| score }.first
  assert(actual_bid == expected_bid,
    "the shared table rule still chose #{actual_bid} instead of #{expected_bid} for an observed match hand")
end

# Across random deals, the private hand estimator should distribute the full
# trick supply between the players. This is an absolute calibration check, not
# merely a comparison with an older policy that may share the same bias.
(3..6).each do |player_count|
  calibration_players = GameRoomParticipants.bots_for(500 + player_count * 10, player_count)
  estimates = []
  80.times do |index|
    hands = game.send(
      :deal_hands,
      calibration_players,
      index % player_count,
      format("%032x", 20_000 + player_count * 1_000 + index)
    )
    calibration_state = { players: calibration_players, hands: hands }
    calibration_players.each do |player|
      estimates << game.send(:estimated_bot_bid, calibration_state, player)
    end
  end
  actual_mean = estimates.sum.to_f / estimates.length
  fair_mean = game.send(:cards_per_player, player_count).to_f / player_count
  assert((actual_mean - fair_mean).abs < 0.20,
    "the #{player_count}-player bid estimator is not calibrated: " \
      "estimated #{actual_mean.round(3)}, expected #{fair_mean.round(3)}")
end

# Threat correction is intentionally exceptional. On a stable sample of exact
# three-player deals it should remain inactive for most hands and have only a
# small average pressure, otherwise a targeted contract audit would silently
# turn into globally conservative bidding.
threat_sample_players = GameRoomParticipants.bots_for(579, 3)
threat_pressures = []
80.times do |index|
  hands = game.send(
    :deal_hands,
    threat_sample_players,
    index % 3,
    format("%032x", 70_000 + index)
  )
  threat_sample_players.each do |actor|
    threat_state = {
      players: threat_sample_players,
      options: {
        "score_limit" => 300,
        "team_size" => 0,
        "quicksand" => false,
        "omniscient_bots" => true
      },
      scores: threat_sample_players.to_h { |player| [player, 0] },
      bids: {},
      hands: hands
    }
    estimate = game.send(:estimated_bot_bid, threat_state, actor)
    planned = [[estimate.round, 1].max, 17].min
    threat = game.send(
      :bot_bid_threat_context,
      threat_state,
      actor,
      { raw_scores: { planned => 1.0 } }
    )
    threat_pressures << threat[:pressure]
  end
end
threat_active_ratio = threat_pressures.count { |pressure| pressure > 0.0 }.to_f /
  threat_pressures.length
threat_mean = threat_pressures.sum.to_f / threat_pressures.length
assert(threat_active_ratio < 0.15,
  "bid threat correction became global: active for #{(threat_active_ratio * 100).round(1)}% of hands")
assert(threat_mean < 0.12,
  "bid threat correction became too strong on average: #{threat_mean.round(3)}")

denial_state = Marshal.load(Marshal.dump(probability_state))
denial_state[:hands]["A"] = %w[TH]
denial_state[:bids] = { "A" => 1, "B" => 6, "C" => 10 }
denial_state[:tricks] = { "A" => 1, "B" => 5, "C" => 3 }
denial_state[:current_trick] = [
  { player: "B", card: "9H" },
  { player: "C", card: "8H" }
]
denial_context = {
  unseen_cards: game.send(:deck_for, 3) - %w[TH 9H 8H],
  void_suits: {},
  cheapest_winner: "TH",
  highest_loser: nil,
  score: { deficit: 0.0, bags: 0 }
}
denial_features = game.send(:playing_bot_features,
  Struct.new(:state).new(denial_state), "A", { "card" => "TH" }, denial_context)
assert(denial_features["deny_opponent_contract"] > 0.0,
  "the bot cannot value stealing a contract trick from an opponent")
assert(denial_features["force_opponent_set"] == 1.0,
  "the bot does not recognize a move that mathematically sets an opponent")
assert(denial_features["tight_table_denial"] > 0.0,
  "the bot ignores contract denial at a tightly bid table")

team_nil_state = Marshal.load(Marshal.dump(probability_state))
team_nil_state[:players] = %w[A B C D]
team_nil_state[:options]["team_size"] = 2
team_nil_state[:options][GameRoomTeams::OPTION_KEY] = [0, 0, 1, 1]
team_nil_state[:scores] = { "team:0" => 0, "team:1" => 0 }
team_nil_state[:bids] = { "A" => 1, "B" => 0, "C" => 1, "D" => 1 }
team_nil_state[:tricks] = { "A" => 1, "B" => 0, "C" => 0, "D" => 0 }
team_nil_state[:hands]["A"] = %w[2H TH AH 2C 3C 4C 5C 6C 7C 8C 9C TC JC]
team_nil_context = probability_context.merge(
  unseen_cards: game.send(:deck_for, 4) - team_nil_state[:hands]["A"]
)
nil_cover = game.send(:playing_bot_features,
  Struct.new(:state).new(team_nil_state), "A", { "card" => "AH" }, team_nil_context)
assert(nil_cover["partner_nil_control"] == 0.0,
  "leading and direct nil control cannot be tuned independently")
assert(nil_cover["partner_nil_lead_control"] == 1.0,
  "the bot cannot lead a winner under which its active nil partner can discard")
assert(nil_cover["unneeded_win_probability"] == 0.0,
  "bag avoidance competes with protection of an active partner nil")
team_nil_state[:current_trick] = [{ player: "C", card: "8H" }]
control_before_partner = game.send(:playing_bot_features,
  Struct.new(:state).new(team_nil_state), "A", { "card" => "AH" }, team_nil_context)
assert(control_before_partner["partner_nil_control"] == 1.0,
  "the bot does not take control before its active nil partner has to play")
team_nil_state[:players] = %w[A C B D]
team_nil_state[:options][GameRoomTeams::OPTION_KEY] = [0, 1, 0, 1]
distant_control = game.send(:playing_bot_features,
  Struct.new(:state).new(team_nil_state), "A", { "card" => "AH" }, team_nil_context)
assert(distant_control["partner_nil_control"] == 0.0 &&
  distant_control["partner_nil_distant_control"] == 1.0,
  "direct and distant nil protection cannot be tuned independently")
team_nil_state[:players] = %w[A B C D]
team_nil_state[:options][GameRoomTeams::OPTION_KEY] = [0, 0, 1, 1]
team_nil_state[:current_trick] = [
  { player: "B", card: "9H" },
  { player: "C", card: "8H" },
  { player: "D", card: "7H" }
]
team_nil_context[:cheapest_winner] = "TH"
cheap_cover = game.send(:playing_bot_features,
  Struct.new(:state).new(team_nil_state), "A", { "card" => "TH" }, team_nil_context)
expensive_cover = game.send(:playing_bot_features,
  Struct.new(:state).new(team_nil_state), "A", { "card" => "AH" }, team_nil_context)
team_policy = default_policy_set.for_state(team_nil_state)
assert(team_policy.score("playing", cheap_cover) > team_policy.score("playing", expensive_cover),
  "the bot wastes its highest card when a lower card already protects the partner nil")
team_nil_state[:current_trick] = []
team_nil_state[:tricks]["B"] = 1
broken_nil = game.send(:playing_bot_features,
  Struct.new(:state).new(team_nil_state), "A", { "card" => "AH" }, team_nil_context)
assert(broken_nil["partner_nil_control"] == 0.0,
  "the bot keeps protecting a partner nil after it has been broken")
assert(broken_nil["unneeded_win_probability"] > 0.0,
  "the team does not resume bag avoidance after its partner nil is broken")

# A completed contract may safely feed a mathematically certain overtrick to an
# opponent who is close to the ten-bag penalty. Restrict this fixed correction
# to the final seat so it never guesses who will ultimately take the trick.
bag_feed_state = {
  players: %w[A B C],
  options: { "score_limit" => 300, "team_size" => 0, "quicksand" => false },
  scores: { "A" => 50, "B" => 99, "C" => 0 },
  bids: { "A" => 1, "B" => 1, "C" => 1 },
  tricks: { "A" => 1, "B" => 1, "C" => 0 },
  hands: { "A" => %w[2H AH], "B" => [], "C" => [] },
  current_trick: [
    { player: "B", card: "KH" },
    { player: "C", card: "QH" }
  ],
  current_player: "A",
  spades_broken: true,
  phase: :playing
}
ninth_bag_feed = game.send(
  :bot_opponent_bag_pressure_score_adjustment,
  bag_feed_state,
  "A",
  { "card" => "2H" }
)
winning_instead = game.send(
  :bot_opponent_bag_pressure_score_adjustment,
  bag_feed_state,
  "A",
  { "card" => "AH" }
)
assert(ninth_bag_feed > 0.0 && winning_instead == 0.0,
  "the bot cannot safely feed a ninth-bag opponent a certain overtrick")
eight_bag_state = Marshal.load(Marshal.dump(bag_feed_state))
eight_bag_state[:scores]["B"] = 98
eighth_bag_feed = game.send(
  :bot_opponent_bag_pressure_score_adjustment,
  eight_bag_state,
  "A",
  { "card" => "2H" }
)
assert(ninth_bag_feed > eighth_bag_feed && eighth_bag_feed > 0.0,
  "opponent bag pressure does not increase near the ten-bag penalty")
unfinished_contract_state = Marshal.load(Marshal.dump(bag_feed_state))
unfinished_contract_state[:tricks]["A"] = 0
assert(game.send(
  :bot_opponent_bag_pressure_score_adjustment,
  unfinished_contract_state,
  "A",
  { "card" => "2H" }
) == 0.0, "the bot sacrifices a trick before making its own contract")

# Nil bidding receives a small shared correction from information genuinely
# available at the table: bidding position and already announced bids. This is
# deliberately outside trained profile weights so every variant uses the same
# conservative interpretation without retraining.
nil_bid_state = {
  players: %w[A B C D],
  options: {
    "score_limit" => 300,
    "team_size" => 2,
    GameRoomTeams::OPTION_KEY => [0, 1, 0, 1],
    "quicksand" => false
  },
  scores: { "team:0" => 0, "team:1" => 0 },
  bids: { "A" => 4, "B" => 1, "C" => 4 },
  tricks: { "A" => 0, "B" => 0, "C" => 0, "D" => 0 },
  hands: { "A" => [], "B" => [], "C" => [], "D" => [] },
  current_trick: [],
  current_player: "D",
  spades_broken: false,
  phase: :bidding
}
weak_partner_nil = game.send(:bot_nil_bid_context_score_adjustment, nil_bid_state, "D", 0)
strong_partner_state = Marshal.load(Marshal.dump(nil_bid_state))
strong_partner_state[:bids]["B"] = 5
strong_partner_nil = game.send(
  :bot_nil_bid_context_score_adjustment, strong_partner_state, "D", 0
)
assert(strong_partner_nil > weak_partner_nil,
  "a known strong partner does not make a nil bid safer")
low_opponent_state = Marshal.load(Marshal.dump(nil_bid_state))
low_opponent_state[:bids] = { "A" => 1, "B" => 3, "C" => 1 }
high_opponent_state = Marshal.load(Marshal.dump(nil_bid_state))
high_opponent_state[:bids] = { "A" => 5, "B" => 3, "C" => 5 }
assert(
  game.send(:bot_nil_bid_context_score_adjustment, high_opponent_state, "D", 0) >
    game.send(:bot_nil_bid_context_score_adjustment, low_opponent_state, "D", 0),
  "known high opponent bids do not modestly improve nil cover prospects"
)
first_nil_state = Marshal.load(Marshal.dump(nil_bid_state))
first_nil_state[:options]["team_size"] = 0
first_nil_state[:options].delete(GameRoomTeams::OPTION_KEY)
first_nil_state[:players] = %w[A B C]
first_nil_state[:scores] = { "A" => 0, "B" => 0, "C" => 0 }
first_nil_state[:bids] = {}
last_nil_state = Marshal.load(Marshal.dump(first_nil_state))
last_nil_state[:bids] = { "A" => 6, "B" => 6 }
assert(
  game.send(:bot_nil_bid_context_score_adjustment, last_nil_state, "C", 0) >
    game.send(:bot_nil_bid_context_score_adjustment, first_nil_state, "A", 0),
  "bidding first is not treated as a more uncertain nil position"
)
assert(game.send(:bot_nil_bid_context_score_adjustment, nil_bid_state, "D", 1) == 0.0,
  "nil context changes ordinary non-zero bids")

strategy = SpadesLearning::Strategy.new(policy: policy)
chosen = strategy.choose(
  actions: environment.legal_actions(actor),
  actor: actor,
  random_source: environment.random_source,
  game: game,
  replay: environment.replay
)
assert(environment.legal_actions(actor).include?(chosen), "the learned policy selected an illegal card")

rotation_scenarios = [
  *SpadesLearning::ScenarioMatrix.for_arrangement('standard_team', player_count: 4, team_size: 2, score_limits: [30]),
  *SpadesLearning::ScenarioMatrix.for_arrangement('standard_individual', player_count: 3, team_size: 0, score_limits: [30])
]
arena = SpadesLearning::Arena.new(game: game, scenarios: rotation_scenarios)
evaluation = arena.compare(candidate: policy, opponent: policy, seeds: [101])
assert(evaluation.games == 5, "the Spades arena did not rotate every team and individual seat")
assert(evaluation.wins == 2, "equal Spades policies did not win the expected rotated seats")
assert(evaluation.losses == 3, "equal Spades policies did not lose the expected rotated seats")
assert((evaluation.average_reward + 0.2).abs < 0.0001, "the rotated self-play reference changed")
assert(evaluation.neutral_wins == 2, "the arena has a wrong neutral result")
assert(evaluation.candidate_bid_error >= 0.0, "the arena did not measure candidate bid error")
assert(evaluation.opponent_bid_error >= 0.0, "the arena did not measure opponent bid error")
assert(evaluation.average_table_bid_gap >= 0.0, "the arena did not measure table bid balance")
assert(evaluation.candidate_contract_rate.between?(0.0, 1.0),
  "the arena reported an invalid candidate contract rate")
assert(evaluation.opponent_contract_rate.between?(0.0, 1.0),
  "the arena reported an invalid opponent contract rate")
assert(evaluation.candidate_average_overtricks >= 0.0,
  "the arena reported negative candidate overtricks")
assert(evaluation.candidate_average_shortfall >= 0.0,
  "the arena reported a negative candidate contract shortfall")
assert(evaluation.average_actions > 0.0, "the arena did not measure match duration in actions")
assert(evaluation.average_rounds > 0.0, "the arena did not measure match duration in rounds")

quality_sample = SpadesLearning::Evaluation.new(
  candidate_contract_rate: 0.8,
  opponent_contract_rate: 0.8,
  candidate_bid_error: 0.5,
  opponent_bid_error: 0.5,
  candidate_bid_bias: 0.1,
  opponent_bid_bias: 0.1,
  candidate_average_overtricks: 1.0,
  opponent_average_overtricks: 0.0,
  candidate_average_shortfall: 0.2,
  opponent_average_shortfall: 0.2
)
assert(quality_sample.quality_advantage(quicksand: true) <
  quality_sample.quality_advantage(quicksand: false),
  "Quicksand training does not penalize overtricks more strongly than standard Spades")

expected_games = {
  "standard_individual" => 18,
  "standard_team" => 7,
  "quicksand_individual" => 18,
  "quicksand_team" => 7
}
SpadesLearning::PROFILE_KEYS.each do |profile|
  scenarios = SpadesLearning::ScenarioMatrix.for_profile(profile, score_limits: [30])
  expanded = SpadesLearning::Arena.new(game: game, scenarios: scenarios).compare(
    candidate: policy,
    opponent: policy,
    seeds: [7_001]
  )
  assert(expanded.games == expected_games.fetch(profile), "#{profile} skipped a player or team arrangement")
  assert(expanded.wins == scenarios.length, "#{profile} does not have a neutral rotated result")
  assert(expanded.neutral_wins == scenarios.length, "#{profile} reports a wrong neutral threshold")
  assert(expanded.average_margin.abs < 0.0001, "#{profile} rotation is biased")
end

trainer = SpadesLearning::SelfPlayTrainer.new(
  game: game,
  policy: policy,
  seed: 9,
  scenarios: rotation_scenarios
)
report = trainer.train(generations: 1, population: 2, evaluation_seeds: 1)
assert(report.generations == 1, "Spades self-play skipped a generation")
assert(report.history.length == 1, "Spades self-play produced no training history")

puts "Spades self-play learning tests passed"
