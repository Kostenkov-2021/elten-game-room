def _(text)
  text
end

require_relative "../../../games/spades"

def assert(condition, message)
  raise message if !condition
end

ReplayForPlanner = Struct.new(:state, :accepted_events, :players)

game = GameRoomGames::Spades.new
players = ["papierek", "bot:66:1", "bot:66:2"]
observed_state = {
  players: players,
  options: {
    "score_limit" => 300,
    "team_size" => 0,
    "no_hell" => false,
    "quicksand" => false,
    "suicide" => false,
    "omniscient_bots" => true
  },
  scores: players.each_with_object({}) { |player, scores| scores[player] = 0 },
  round: 1,
  dealer_index: 0,
  bids: { "papierek" => 5 },
  tricks: players.each_with_object({}) { |player, tricks| tricks[player] = 0 },
  hands: {
    "papierek" => %w[5D 8S TH TD 3D JS 2D 3H KC 5C KS 9S AH 9D 4S 5H QH],
    "bot:66:1" => %w[QD 2S JD 4D 7S 6S 7H 2H 7C 4C 8H 3C 5S 6C TC KD 9H],
    "bot:66:2" => %w[AS QC QS 3S 6D JC 9C 8C 4H AC AD 6H TS JH KH 7D 8D]
  },
  current_trick: [],
  current_player: "bot:66:1",
  spades_broken: false,
  phase: :bidding,
  winner: nil
}
replay = ReplayForPlanner.new(observed_state, [], players)
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
omniscient_context = game.bot_decision_context(replay, "bot:66:1")
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
plan = omniscient_context.fetch(:round_plan)
assert(plan[:exact_information] == true, "the exact deal did not reach the round planner")
assert(plan[:worlds] == 1, "the omniscient planner invented alternative deals")
assert(plan[:scores].key?(2) && plan[:scores].key?(3), "the planner did not score legal bids")
assert(plan[:raw_scores][2] > plan[:raw_scores][3],
  "the complete-round planner still prefers the failed bid of three in the observed deal")
observed_choice = game.bot_strategy.choose(
  actions: game.legal_actions(replay, "bot:66:1"),
  actor: "bot:66:1",
  random_source: GameRoomRandom::SeededSource.new(882),
  game: game,
  replay: replay
)
assert(observed_choice["bid"] == 2,
  "the complete bot policy still bids #{observed_choice['bid']} instead of two in the observed deal")

# Technical table and participant ids are transport details, not strategic
# information. Renaming every player without changing their seats, hands or
# public state must preserve both the sampled continuations and the decision.
rename_players = lambda do |source, replacements|
  renamed = Marshal.load(Marshal.dump(source))
  mapping = source[:players].zip(replacements).to_h
  renamed[:players] = replacements.dup
  [:scores, :bids, :tricks, :hands].each do |name|
    renamed[name] = renamed[name].each_with_object({}) do |(key, value), result|
      result[mapping.fetch(key, key)] = value
    end
  end
  renamed[:units] = renamed[:units].map { |unit| mapping.fetch(unit, unit) } if renamed[:units].is_a?(Array)
  renamed[:current_player] = mapping.fetch(renamed[:current_player], renamed[:current_player])
  renamed[:winner] = mapping.fetch(renamed[:winner], renamed[:winner])
  renamed[:current_trick].each do |play|
    play[:player] = mapping.fetch(play[:player], play[:player])
  end
  renamed
end
renamed_players = ["renamed-user", "bot:999:7", "bot:999:4"]
renamed_state = rename_players.call(observed_state, renamed_players)
renamed_actor = renamed_players[1]
renamed_replay = ReplayForPlanner.new(renamed_state, [], renamed_players)
planner = game.send(:spades_round_planner)
assert(
  planner.send(:public_seed, observed_state, "bot:66:1") ==
    planner.send(:public_seed, renamed_state, renamed_actor),
  "technical participant ids still change the planner seed"
)
renamed_context = game.bot_decision_context(renamed_replay, renamed_actor)
assert(plan[:raw_scores] == renamed_context.fetch(:round_plan).fetch(:raw_scores),
  "renaming participants still changes complete-round planning")
renamed_choice = game.bot_strategy.choose(
  actions: game.legal_actions(renamed_replay, renamed_actor),
  actor: renamed_actor,
  random_source: GameRoomRandom::SeededSource.new(882),
  game: game,
  replay: renamed_replay
)
assert(renamed_choice == observed_choice,
  "renaming participants changed the selected Spades action")

# Live build-58 regression: the omniscient nil bidder followed 3C with QC,
# although the final player could duck with TC and deliberately set the nil.
# 9C is the highest card that cannot be ducked in this exact deal.
nil_players = ["papierek", "bot:68:1", "bot:68:2"]
nil_state = {
  players: nil_players,
  options: {
    "score_limit" => 300,
    "team_size" => 0,
    "no_hell" => false,
    "quicksand" => false,
    "suicide" => false,
    "omniscient_bots" => true
  },
  scores: nil_players.each_with_object({}) { |player, scores| scores[player] = 0 },
  round: 1,
  dealer_index: 0,
  bids: { "bot:68:1" => 4, "bot:68:2" => 0, "papierek" => 10 },
  tricks: nil_players.each_with_object({}) { |player, tricks| tricks[player] = 0 },
  hands: {
    "papierek" => %w[KH 6D AC 2D KS AS KD KC 7S 2H AD QH 4H 3S JD 2S TC],
    "bot:68:1" => %w[QS 8S 5C 7H 7C 9D JH 5H 9S TS 5S JS 8D 4C 8H 6S],
    "bot:68:2" => %w[QC 3D TD 9C 3H 5D 9H 4S JC 6C 6H 8C QD 7D TH AH 4D]
  },
  current_trick: [{ player: "bot:68:1", card: "3C" }],
  current_player: "bot:68:2",
  spades_broken: false,
  phase: :playing,
  winner: nil
}
nil_replay = ReplayForPlanner.new(nil_state, [], nil_players)
nil_context = game.bot_decision_context(nil_replay, "bot:68:2")
nil_plan = nil_context.fetch(:round_plan)
assert(nil_plan[:raw_scores]["9C"] > nil_plan[:raw_scores]["QC"],
  "the planner still assumes an opponent must cover an unsafe nil card")
nil_choice = game.bot_strategy.choose(
  actions: game.legal_actions(nil_replay, "bot:68:2"),
  actor: "bot:68:2",
  random_source: GameRoomRandom::SeededSource.new(883),
  game: game,
  replay: nil_replay
)
assert(nil_choice["card"] == "9C",
  "the nil bidder chose #{nil_choice['card']} instead of the highest guaranteed-safe club")

# Live build-59 regression: with three cards left, leading QC allowed one
# opponent to ruff and the other to overruff the next trick. Leading a low
# spade first forces both opposing spades, after which QC and the final spade
# make the seven-trick contract. Nine cards remain, so this also verifies that
# the exact solver starts before the old six-card boundary.
contract_players = ["papierek", "bot:69:1", "bot:69:2"]
contract_state = {
  players: contract_players,
  options: {
    "score_limit" => 300,
    "team_size" => 0,
    "no_hell" => false,
    "quicksand" => false,
    "suicide" => false,
    "omniscient_bots" => true
  },
  scores: { "papierek" => 31, "bot:69:1" => 70, "bot:69:2" => 60 },
  round: 2,
  dealer_index: 1,
  bids: { "bot:69:2" => 7, "papierek" => 4, "bot:69:1" => 4 },
  tricks: { "papierek" => 4, "bot:69:1" => 5, "bot:69:2" => 5 },
  hands: {
    "papierek" => %w[3C 9S 6C],
    "bot:69:1" => %w[JH 8D 7S],
    "bot:69:2" => %w[5S QC 4S]
  },
  current_trick: [],
  current_player: "bot:69:2",
  spades_broken: true,
  phase: :playing,
  winner: nil
}
contract_replay = ReplayForPlanner.new(contract_state, [], contract_players)
contract_context = game.bot_decision_context(contract_replay, "bot:69:2")
contract_plan = contract_context.fetch(:round_plan)
assert(contract_plan[:raw_scores]["4S"] > contract_plan[:raw_scores]["QC"],
  "the extended exact endgame still treats the failed club lead as equivalent")
contract_choice = game.bot_strategy.choose(
  actions: game.legal_actions(contract_replay, "bot:69:2"),
  actor: "bot:69:2",
  random_source: GameRoomRandom::SeededSource.new(884),
  game: game,
  replay: contract_replay
)
assert(contract_choice["card"] == "4S",
  "the contract bot chose #{contract_choice['card']} instead of clearing opposing spades")

fair_state = Marshal.load(Marshal.dump(observed_state))
fair_state[:options]["omniscient_bots"] = false
fair_replay = ReplayForPlanner.new(fair_state, [], players)
fair_plan = game.bot_decision_context(fair_replay, "bot:66:1").fetch(:round_plan)
swapped = Marshal.load(Marshal.dump(fair_state))
swapped[:hands]["papierek"], swapped[:hands]["bot:66:2"] =
  swapped[:hands]["bot:66:2"], swapped[:hands]["papierek"]
swapped_plan = game.bot_decision_context(
  ReplayForPlanner.new(swapped, [], players), "bot:66:1"
).fetch(:round_plan)
assert(fair_plan[:worlds] > 1, "the fair planner did not sample possible deals")
assert(fair_plan[:raw_scores] == swapped_plan[:raw_scores],
  "the fair planner read the real locations of hidden cards")
renamed_fair_players = ["fair-user", "bot:12345:9", "bot:12345:2"]
renamed_fair_state = rename_players.call(fair_state, renamed_fair_players)
renamed_fair_plan = game.bot_decision_context(
  ReplayForPlanner.new(renamed_fair_state, [], renamed_fair_players),
  renamed_fair_players[1]
).fetch(:round_plan)
assert(fair_plan[:raw_scores] == renamed_fair_plan[:raw_scores],
  "technical participant ids still change fair hidden-hand sampling")

planner = game.send(:spades_round_planner)

# Match-aware evaluation must dominate an ordinary round score only when the
# simulated result actually wins or loses the complete match.
match_players = %w[Alice Bob Carol]
winning_match_state = {
  players: match_players,
  options: {
    "score_limit" => 300,
    "team_size" => 0,
    "quicksand" => false
  },
  scores: { "Alice" => 280, "Bob" => 290, "Carol" => 0 },
  bids: { "Alice" => 3, "Bob" => 3, "Carol" => 1 },
  tricks: { "Alice" => 3, "Bob" => 2, "Carol" => 1 },
  hands: match_players.each_with_object({}) { |player, hands| hands[player] = [] },
  current_trick: [],
  current_player: nil,
  phase: :playing,
  round: 4,
  dealer_index: 0,
  spades_broken: true
}
assert(planner.send(:terminal_utility, winning_match_state, "Alice") > 900.0,
  "a simulated match win was not made decisive")
losing_match_state = Marshal.load(Marshal.dump(winning_match_state))
losing_match_state[:scores] = { "Alice" => 290, "Bob" => 280, "Carol" => 0 }
losing_match_state[:tricks] = { "Alice" => 2, "Bob" => 3, "Carol" => 1 }
assert(planner.send(:terminal_utility, losing_match_state, "Alice") < -900.0,
  "a simulated opponent match win was not made decisive")

# Refinement is additional work: clear ordinary choices stay on the original
# pass, close choices are rechecked, and a changed winner needs a clear margin.
early_bidding_state = Marshal.load(Marshal.dump(winning_match_state))
early_bidding_state[:scores] = { "Alice" => 0, "Bob" => 0, "Carol" => 0 }
early_bidding_state[:phase] = :bidding
assert(planner.send(
  :refinement_needed?, early_bidding_state, "Alice", :bidding, { 2 => 10.0, 3 => 7.0 }
), "a close decision did not request refinement")
assert(!planner.send(
  :refinement_needed?, early_bidding_state, "Alice", :bidding,
  { 2 => 30.0, 3 => 0.0, 4 => -20.0 }
), "a clear ordinary decision was needlessly refined")
assert(!planner.send(
  :refinement_acceptable?, { "2C" => 10.0, "3C" => 9.0 },
  { "2C" => 10.0, "3C" => 12.0 }
), "an uncertain refinement replaced the established preference")
assert(planner.send(
  :refinement_acceptable?, { "2C" => 10.0, "3C" => 9.0 },
  { "2C" => 10.0, "3C" => 20.0 }
), "a decisive refinement could not replace the established preference")

# The normal fair bot may infer hidden cards from public evidence, but never
# from the real hidden-hand locations stored in replay state.
strong_bid_world = Marshal.load(Marshal.dump(early_bidding_state))
strong_bid_world[:bids] = { "Bob" => 5 }
strong_bid_world[:hands] = {
  "Alice" => %w[2D 3D 4D 5D 6D],
  "Bob" => %w[AS KS QS JS AH],
  "Carol" => %w[2C 3C 4C 5C 6C]
}
weak_bid_world = Marshal.load(Marshal.dump(strong_bid_world))
weak_bid_world[:hands]["Bob"], weak_bid_world[:hands]["Carol"] =
  weak_bid_world[:hands]["Carol"], weak_bid_world[:hands]["Bob"]
strong_bid_weight = planner.send(
  :world_likelihood, strong_bid_world, "Alice", { public_plays: [] }
)
weak_bid_weight = planner.send(
  :world_likelihood, weak_bid_world, "Alice", { public_plays: [] }
)
assert(strong_bid_weight > weak_bid_weight,
  "public bidding did not favor the more plausible sampled hand")

nil_play_world = Marshal.load(Marshal.dump(early_bidding_state))
nil_play_world[:bids] = { "Bob" => 0 }
nil_play_world[:hands] = {
  "Alice" => %w[2D 3D 4D],
  "Bob" => %w[KC AC],
  "Carol" => %w[2H 3H 4H]
}
nil_play = [{ player: "Bob", card: "QC" }]
plausible_hands = planner.send(:reconstructed_hands, nil_play_world, nil_play)
plausible_play_weight = planner.send(
  :world_play_likelihood, nil_play_world, plausible_hands, nil_play
)
implausible_nil_world = Marshal.load(Marshal.dump(nil_play_world))
implausible_nil_world[:hands]["Bob"] = %w[2C 3C]
implausible_hands = planner.send(:reconstructed_hands, implausible_nil_world, nil_play)
implausible_play_weight = planner.send(
  :world_play_likelihood, implausible_nil_world, implausible_hands, nil_play
)
assert(plausible_play_weight > implausible_play_weight,
  "a public nil play did not distinguish plausible sampled hands")

# The established twelve-card exact boundary remains the endgame limit. A
# refinement pass must not expand every early hypothetical continuation into
# a substantially larger exact tree.
endgame_state = Marshal.load(Marshal.dump(winning_match_state))
endgame_state[:scores] = { "Alice" => 0, "Bob" => 0, "Carol" => 0 }
endgame_state[:hands] = {
  "Alice" => %w[2C 3C],
  "Bob" => %w[4C 5C 6C 7C 8C 9C],
  "Carol" => %w[2D 3D 4D 5D 6D 7D]
}
endgame_state[:current_player] = "Alice"
endgame_state[:bids] = { "Alice" => 1, "Bob" => 5, "Carol" => 5 }
endgame_state[:tricks] = { "Alice" => 0, "Bob" => 4, "Carol" => 4 }
assert(planner.send(:planning_exact_limit, endgame_state) == 12,
  "the actual endgame changed its established twelve-card exact boundary")

# Live build-63 regression: Computer 2 needed seven of the ten remaining
# tricks, yet ducked QC with JC while holding AC. The round planner saw only a
# narrow difference between both continuations, normalized that small gap to
# the full -1..1 range and overruled the much stronger card policy. A plan
# below the established confidence margin may advise the policy, but must not
# dominate it.
confidence_players = ["papiertestowy", "bot:77:1", "bot:77:2"]
confidence_state = {
  players: confidence_players,
  options: {
    "score_limit" => 300,
    "team_size" => 0,
    "no_hell" => false,
    "quicksand" => false,
    "suicide" => false,
    "omniscient_bots" => true
  },
  scores: { "papiertestowy" => 40, "bot:77:1" => 40, "bot:77:2" => 111 },
  round: 2,
  dealer_index: 0,
  bids: { "bot:77:1" => 5, "bot:77:2" => 8, "papiertestowy" => 3 },
  tricks: { "papiertestowy" => 3, "bot:77:1" => 3, "bot:77:2" => 1 },
  hands: {
    "papiertestowy" => %w[8S 2H 4C KS KC 6C QS 5C 9C],
    "bot:77:1" => %w[JS 5H 4H KH 2S 7S 4S 7D 3H],
    "bot:77:2" => %w[3S TS 9S JC AH TD AC AS 5S TH]
  },
  current_trick: [
    { player: "papiertestowy", card: "QC" },
    { player: "bot:77:1", card: "TC" }
  ],
  current_player: "bot:77:2",
  spades_broken: true,
  phase: :playing,
  winner: nil
}
confidence_plays = [
  ["bot:77:1", "AD"], ["bot:77:2", "3D"], ["papiertestowy", "JD"],
  ["bot:77:1", "7C"], ["bot:77:2", "3C"], ["papiertestowy", "8C"],
  ["papiertestowy", "9H"], ["bot:77:1", "JH"], ["bot:77:2", "7H"],
  ["bot:77:1", "5D"], ["bot:77:2", "4D"], ["papiertestowy", "9D"],
  ["papiertestowy", "2D"], ["bot:77:1", "QD"], ["bot:77:2", "KD"],
  ["bot:77:2", "8H"], ["papiertestowy", "6H"], ["bot:77:1", "QH"],
  ["bot:77:1", "6D"], ["bot:77:2", "8D"], ["papiertestowy", "6S"],
  ["papiertestowy", "QC"], ["bot:77:1", "TC"]
].each_with_index.map do |(actor, card), index|
  { "__id" => 10_000 + index, "action" => "play", "actor" => actor, "value" => card }
end
confidence_plays.unshift({ "__id" => 9_999, "action" => "deal", "actor" => "system" })
confidence_replay = ReplayForPlanner.new(confidence_state, confidence_plays, confidence_players)
confidence_context = game.bot_decision_context(confidence_replay, "bot:77:2")
assert(confidence_context[:round_plan][:confidence] < GameRoomGames::Spades::PLANNING_FULL_CONFIDENCE_MARGIN,
  "the reproduced uncertain club decision unexpectedly became decisive")
confidence_choice = game.bot_strategy.choose(
  actions: game.legal_actions(confidence_replay, "bot:77:2"),
  actor: "bot:77:2",
  random_source: GameRoomRandom::SeededSource.new(885),
  game: game,
  replay: confidence_replay
)
assert(confidence_choice["card"] == "AC",
  "the low-confidence planner still overruled AC with #{confidence_choice['card']}")

# Live build-78 regression: Computer 2 was last to play, needed two more tricks
# for a six-trick contract and could win the current trick with either 7S or AS.
# It spent AS, although playing 7S made the same trick and retained the certain
# ace for the final required trick. If only the current trick is still needed,
# the preference reverses: burning AS avoids retaining a forced overtrick.
conservation_players = ["papierek", "bot:114:1", "bot:114:2"]
conservation_state = {
  players: conservation_players,
  options: {
    "score_limit" => 300,
    "team_size" => 0,
    "no_hell" => false,
    "quicksand" => false,
    "suicide" => false,
    "omniscient_bots" => true
  },
  scores: conservation_players.each_with_object({}) { |player, scores| scores[player] = 0 },
  round: 1,
  dealer_index: 0,
  bids: { "bot:114:1" => 5, "bot:114:2" => 6, "papierek" => 5 },
  tricks: { "papierek" => 4, "bot:114:1" => 2, "bot:114:2" => 4 },
  hands: {
    "papierek" => %w[KS 9S 9C TS 7C TC],
    "bot:114:1" => %w[JD TD 7H QS 8S JS],
    "bot:114:2" => %w[QH TH 7S JH 2S AS KH]
  },
  current_trick: [
    { player: "papierek", card: "QC" },
    { player: "bot:114:1", card: "4S" }
  ],
  current_player: "bot:114:2",
  spades_broken: true,
  phase: :playing,
  winner: nil
}
low_conservation = game.bot_policy_score_adjustment(
  conservation_state, "bot:114:2", { "card" => "7S" }, {}
)
high_conservation = game.bot_policy_score_adjustment(
  conservation_state, "bot:114:2", { "card" => "AS" }, {}
)
assert(low_conservation > high_conservation,
  "the shared policy still spends AS instead of preserving it behind 7S")

secured_state = Marshal.load(Marshal.dump(conservation_state))
secured_state[:tricks]["bot:114:2"] = 5
secured_low = game.bot_policy_score_adjustment(
  secured_state, "bot:114:2", { "card" => "7S" }, {}
)
secured_high = game.bot_policy_score_adjustment(
  secured_state, "bot:114:2", { "card" => "AS" }, {}
)
assert(secured_high > secured_low,
  "a mathematically secured contract still preserves the avoidable ace overtrick")

# Live build-80 regression, table 125, round 1: Computer 2 needed one more
# trick. The complete-round planner correctly valued every lead except 9H
# eighty points higher, but several good leads tied for first place. The old
# confidence calculation interpreted that tie as zero confidence and discarded
# the only useful conclusion: 9H was decisively dominated. The local policy
# then selected exactly that losing lead and the four-trick contract failed.
dominated_players = ["papierek", "bot:125:1", "bot:125:2"]
dominated_state = {
  players: dominated_players,
  options: {
    "score_limit" => 300,
    "team_size" => 0,
    "no_hell" => false,
    "quicksand" => false,
    "suicide" => false,
    "omniscient_bots" => true
  },
  units: dominated_players,
  scores: dominated_players.each_with_object({}) { |player, scores| scores[player] = 0 },
  round: 1,
  dealer_index: 0,
  bids: { "bot:125:1" => 4, "bot:125:2" => 4, "papierek" => 9 },
  tricks: { "papierek" => 1, "bot:125:1" => 4, "bot:125:2" => 3 },
  hands: {
    "papierek" => %w[KS 8S 9S QS 5H AS 7S TS JS],
    "bot:125:1" => %w[TH 8D 6S 9D 3D KD QD JH TD],
    "bot:125:2" => %w[AD 3S 2S 9H 6D JC 4S 5D 4D]
  },
  current_trick: [],
  current_player: "bot:125:2",
  spades_broken: true,
  phase: :playing,
  winner: nil
}
dominated_replay = ReplayForPlanner.new(dominated_state, [], dominated_players)
dominated_context = game.bot_decision_context(dominated_replay, "bot:125:2")
dominated_raw = dominated_context.fetch(:round_plan).fetch(:raw_scores)
assert(dominated_raw.values.max - dominated_raw.fetch("9H") >= 40.0,
  "the reproduced contract lead is no longer decisively dominated")
dominated_choice = game.bot_strategy.choose(
  actions: game.legal_actions(dominated_replay, "bot:125:2"),
  actor: "bot:125:2",
  random_source: GameRoomRandom::SeededSource.new(886),
  game: game,
  replay: dominated_replay
)
assert(dominated_choice["card"] != "9H",
  "the bot still ignored the planner and selected the dominated 9H lead")

# Live build-82 regression, table 127, round 4: Computer 2 still needed all
# five contracted tricks and could take KC with AC. A heuristic early-round
# rollout projected that AC would let Computer 1 cross the 300-point match
# limit, so the low-confidence dominated-choice exception assigned AC the full
# -24 veto. Knowing every hand is not the same as solving all 41 remaining
# cards exactly. The lone-ace rule can legitimately change the confidence of
# this complete-round projection, but AC must remain the selected continuation.
# Test the approximate terminal-match safeguard independently of that mutable
# deal shape so it remains subject to normal confidence scaling.
match_players = ["papierek", "bot:127:1", "bot:127:2"]
match_state = {
  players: match_players,
  options: {
    "score_limit" => 300,
    "team_size" => 0,
    "no_hell" => false,
    "quicksand" => false,
    "suicide" => false,
    "omniscient_bots" => true
  },
  units: match_players,
  scores: { "papierek" => 41, "bot:127:1" => 253, "bot:127:2" => 141 },
  round: 4,
  dealer_index: 2,
  bids: { "papierek" => 5, "bot:127:1" => 7, "bot:127:2" => 5 },
  tricks: { "papierek" => 2, "bot:127:1" => 1, "bot:127:2" => 0 },
  hands: {
    "papierek" => %w[8H TD TH 9D QH 5S JD JS 2H 6D JH 8D 8C AS],
    "bot:127:1" => %w[QS 8S 6S 4D 5C 7H 3C 7S AH 2S 6H 3S KH],
    "bot:127:2" => %w[3H 6C QD TS 4H 9H TC 4S AC 7C JC 9S 5H KS]
  },
  current_trick: [{ player: "bot:127:1", card: "KC" }],
  current_player: "bot:127:2",
  spades_broken: false,
  phase: :playing,
  winner: nil
}
match_plays = [
  ["papierek", "AD"], ["bot:127:1", "2D"], ["bot:127:2", "5D"],
  ["papierek", "KD"], ["bot:127:1", "3D"], ["bot:127:2", "7D"],
  ["papierek", "9C"], ["bot:127:1", "QC"], ["bot:127:2", "4C"],
  ["bot:127:1", "KC"]
].each_with_index.map do |(actor, card), index|
  { "__id" => 20_000 + index, "action" => "play", "actor" => actor, "value" => card }
end
match_plays.unshift({ "__id" => 19_999, "action" => "deal", "actor" => "system" })
match_replay = ReplayForPlanner.new(match_state, match_plays, match_players)
match_context = game.bot_decision_context(match_replay, "bot:127:2")
match_plan = match_context.fetch(:round_plan)
match_choice = game.bot_strategy.choose(
  actions: game.legal_actions(match_replay, "bot:127:2"),
  actor: "bot:127:2",
  random_source: GameRoomRandom::SeededSource.new(888),
  game: game,
  replay: match_replay
)
assert(match_choice["card"] == "AC",
  "the approximate match projection still overruled AC with #{match_choice['card']}")
approximate_plan = {
  exact_information: true,
  exact_limit: match_plan[:exact_limit],
  confidence: 0.0,
  scores: { "AC" => -1.0, "6C" => 0.0 },
  raw_scores: { "AC" => -974.5, "6C" => -61.7 }
}
approximate_adjustment = game.bot_planning_score_adjustment(
  match_state,
  "bot:127:2",
  { "card" => "AC" },
  { round_plan: approximate_plan }
)
assert(approximate_adjustment == 0.0,
  "an uncertain approximate terminal-match loss bypassed confidence scaling")

# The same protection must not disable a genuinely exact terminal-match veto.
exact_match_state = Marshal.load(Marshal.dump(match_state))
exact_match_state[:hands] = {
  "papierek" => %w[8C AS],
  "bot:127:1" => %w[KH QS],
  "bot:127:2" => %w[6C AC]
}
exact_match_plan = {
  exact_information: true,
  exact_limit: 9,
  confidence: 0.0,
  scores: { "6C" => 1.0, "AC" => -1.0 },
  raw_scores: { "6C" => -61.704, "AC" => -974.5 }
}
exact_match_adjustment = game.bot_planning_score_adjustment(
  exact_match_state,
  "bot:127:2",
  { "card" => "AC" },
  { round_plan: exact_match_plan }
)
assert(exact_match_adjustment == -GameRoomGames::Spades::PLANNING_DOMINATED_CHOICE_PENALTY,
  "an exact terminal-match loss no longer receives the dominated-choice veto")

# Live build-80 regression, table 125, round 3: Computer 2 declared nil while
# holding 5D and 6D. Once Computer 1 obtained the lead, 2D forced the nil bidder
# to win: it had to follow with at least 5D and the last player could duck with
# 4D. Complete-round rollouts must model this hostile lead instead of treating
# the nil as safe simply because no dangerous trick is in progress yet.
forced_nil_state = {
  players: dominated_players,
  options: dominated_state[:options].dup,
  units: dominated_players,
  scores: { "papierek" => 150, "bot:125:1" => 92, "bot:125:2" => 10 },
  round: 3,
  dealer_index: 2,
  bids: { "papierek" => 10, "bot:125:1" => 2 },
  tricks: dominated_players.each_with_object({}) { |player, tricks| tricks[player] = 0 },
  hands: {
    "papierek" => %w[TD 4S TS 8S AH QS QD AC JD 9D 5S 4H 2S AS 4D AD KS],
    "bot:125:1" => %w[7S QH 8C 3D KD 6H TC 7D 2D 8D 7C TH 3H KC 9C QC 9S],
    "bot:125:2" => %w[5C 3S KH 9H 6C JC 6S 2H JH 3C 7H 8H 4C JS 6D 5H 5D]
  },
  current_trick: [],
  current_player: "bot:125:2",
  spades_broken: false,
  phase: :bidding,
  winner: nil
}
forced_nil_replay = ReplayForPlanner.new(forced_nil_state, [], dominated_players)
forced_nil_context = game.bot_decision_context(forced_nil_replay, "bot:125:2")
forced_nil_plan = forced_nil_context.fetch(:round_plan).fetch(:raw_scores)
assert(forced_nil_plan.fetch(0) < [forced_nil_plan.fetch(1), forced_nil_plan.fetch(2)].max,
  "the planner still values the demonstrably forced nil above a regular bid")
forced_nil_choice = game.bot_strategy.choose(
  actions: game.legal_actions(forced_nil_replay, "bot:125:2"),
  actor: "bot:125:2",
  random_source: GameRoomRandom::SeededSource.new(887),
  game: game,
  replay: forced_nil_replay
)
assert(forced_nil_choice["bid"] != 0,
  "the bot still declares the nil that 2D and 4D can force to fail")

# Live build-83 regressions, table 128. The ordinary complete-round bidding
# rollout predicted five tricks in both deals, while its early play model did
# not reproduce a human deliberately attacking the contract. The shared bid
# threat analysis should reject only the exposed fifth trick, not generally
# turn strong bids into conservative ones.
threat_players = ["papierek", "bot:128:1", "bot:128:2"]
threat_options = {
  "score_limit" => 300,
  "team_size" => 0,
  "no_hell" => false,
  "quicksand" => false,
  "suicide" => false,
  "omniscient_bots" => true
}
ruff_threat_state = {
  players: threat_players,
  options: threat_options.dup,
  units: threat_players,
  scores: threat_players.each_with_object({}) { |player, scores| scores[player] = 0 },
  round: 1,
  dealer_index: 2,
  bids: { "papierek" => 5, "bot:128:1" => 6 },
  tricks: threat_players.each_with_object({}) { |player, tricks| tricks[player] = 0 },
  hands: {
    "papierek" => %w[7S 7C 4C JD 2D 4D TS QC 6C 3D QS KC 6S JS TC 5S 9D],
    "bot:128:1" => %w[2S AD AC QH 4S 9H KH 8H 5C 5H QD 9S 3S 4H 9C TD 7D],
    "bot:128:2" => %w[5D KS 6H 8C KD AH JC 2H 3C TH AS 6D 8D JH 3H 8S 7H]
  },
  current_trick: [],
  current_player: "bot:128:2",
  spades_broken: false,
  phase: :bidding,
  winner: nil
}
weak_trump_state = {
  players: threat_players,
  options: threat_options.dup,
  units: threat_players,
  scores: { "papierek" => 51, "bot:128:1" => 61, "bot:128:2" => -50 },
  round: 2,
  dealer_index: 0,
  bids: { "bot:128:1" => 7 },
  tricks: threat_players.each_with_object({}) { |player, tricks| tricks[player] = 0 },
  hands: {
    "papierek" => %w[5H QC JH KS 4H 5D AH QD TH JC 5S 4C 6S TS QS 7D 6C],
    "bot:128:1" => %w[5C 6D 9C QH KH JS 7C KD 2S JD 8C 3C AS 2H 7S 9S 3S],
    "bot:128:2" => %w[8H 6H AD TD KC 3H TC 3D 7H AC 8D 4D 8S 9D 2D 9H 4S]
  },
  current_trick: [],
  current_player: "bot:128:2",
  spades_broken: false,
  phase: :bidding,
  winner: nil
}
[
  [ruff_threat_state, 889],
  [weak_trump_state, 890]
].each do |threat_state, seed|
  threat_replay = ReplayForPlanner.new(threat_state, [], threat_players)
  threat_choice = game.bot_strategy.choose(
    actions: game.legal_actions(threat_replay, "bot:128:2"),
    actor: "bot:128:2",
    random_source: GameRoomRandom::SeededSource.new(seed),
    game: game,
    replay: threat_replay
  )
  assert(threat_choice["bid"] == 4,
    "the threat-aware bidder still chose #{threat_choice['bid']} instead of four")
end

loaded_context = game.bot_decision_context(
  ReplayForPlanner.new(weak_trump_state, [], threat_players),
  "bot:128:2"
).fetch(:bid_threat)
relaxed_table_state = Marshal.load(Marshal.dump(weak_trump_state))
relaxed_table_state[:bids] = { "bot:128:1" => 2 }
relaxed_context = game.send(
  :bot_bid_threat_context,
  relaxed_table_state,
  "bot:128:2",
  { raw_scores: { 4 => 18.65, 5 => 25.5 } }
)
assert(loaded_context[:table_pressure] > relaxed_context[:table_pressure],
  "a fully or plausibly fully allocated table did not increase marginal bid risk")
assert(loaded_context[:pressure] <= 1.0,
  "table loading allowed bid threat pressure to exceed its bounded correction")
empty_threat = game.send(
  :bot_bid_threat_context,
  weak_trump_state,
  "bot:128:2",
  { raw_scores: {} }
)
assert(empty_threat[:pressure] == 0.0,
  "an unavailable round plan invented a bid threat correction")

robust_bid_state = Marshal.load(Marshal.dump(ruff_threat_state))
robust_bid_state[:bids] = { "papierek" => 4, "bot:128:1" => 5 }
robust_bid_state[:hands] = {
  "papierek" => %w[2S 3S 4S 2H 3H 4H 5H 6H 2D 3D 4D 5D 6D 3C 4C 5C 6C],
  "bot:128:1" => %w[5S 6S 7S 7H 8H 9H TH JH 7D 8D 9D TD JD 7C 8C 9C TC],
  "bot:128:2" => %w[8S 9S TS JS QS KS AS QH KH AH QD KD AD JC QC KC AC]
}
robust_replay = ReplayForPlanner.new(robust_bid_state, [], threat_players)
robust_estimate = game.send(:estimated_bot_bid, robust_bid_state, "bot:128:2")
robust_context = game.bot_decision_context(robust_replay, "bot:128:2")
robust_choice = game.bot_strategy.choose(
  actions: game.legal_actions(robust_replay, "bot:128:2"),
  actor: "bot:128:2",
  random_source: GameRoomRandom::SeededSource.new(891),
  game: game,
  replay: robust_replay
)
assert(robust_choice["bid"].to_i >= robust_estimate.floor,
  "the threat analysis reduced a mathematically dominant hand to #{robust_choice['bid']}")
assert(robust_context.fetch(:bid_threat).fetch(:pressure) == 0.0,
  "table loading alone penalized a robust high contract")

# Live build-84 regressions, table 130. A top side-suit run is not a set of
# independent certain tricks when a trump-holding opponent has only one or two
# cards in that suit. Computer 1 counted A-K-Q-J of diamonds as four certain
# tricks, although papierek's singleton allowed only one safe cash before a
# ruff. The same shape also made leading a low diamond waste that one window.
latest_players = ["papierek", "bot:130:1", "bot:130:2"]
latest_options = {
  "score_limit" => 300,
  "team_size" => 0,
  "no_hell" => false,
  "quicksand" => false,
  "suicide" => false,
  "omniscient_bots" => true
}
fragile_actor = "bot:130:1"
fragile_state = {
  players: latest_players,
  options: latest_options.dup,
  units: latest_players,
  scores: latest_players.each_with_object({}) { |player, scores| scores[player] = 0 },
  round: 1,
  dealer_index: 2,
  bids: { "papierek" => 4, fragile_actor => 7, "bot:130:2" => 5 },
  tricks: { "papierek" => 1, fragile_actor => 1, "bot:130:2" => 2 },
  hands: {
    "papierek" => %w[4D 5C QC TS 7S 4S 3C JC 4C 9C 3S 6C 5S],
    fragile_actor => %w[AC 8D KS KD 7C JD 8S AS 9H 2S KC QD AD],
    "bot:130:2" => %w[5D 3D TH 4H 6S KH TC TD QS JS 9S 8C 9D]
  },
  current_trick: [],
  current_player: fragile_actor,
  spades_broken: false,
  phase: :playing,
  winner: nil
}
diamond_profile = game.send(
  :exact_side_suit_control_profile, fragile_state, fragile_actor
).fetch("D")
assert(diamond_profile[:control_cards] == %w[AD KD QD JD],
  "the exact control model did not find the A-K-Q-J diamond run")
assert(diamond_profile[:safe_controls] == 1 && diamond_profile[:threatened_controls] == 3,
  "a singleton opponent did not limit four diamond controls to one safe cash")
nominal_controls = game.send(:estimated_public_certain_tricks, fragile_state, fragile_actor)
safe_controls = game.send(:estimated_certain_tricks, fragile_state, fragile_actor)
assert(nominal_controls == 8 && safe_controls == 5,
  "the fragile deal still reports exposed nominal controls as certain tricks")
expiring = game.bot_expiring_contract_control(
  fragile_state,
  fragile_actor,
  { known_hands: fragile_state[:hands], omniscient: true }
)
assert(expiring != nil && expiring[:suit] == "D" && expiring[:preferred] == "JD",
  "the bot did not identify the cheapest safe diamond cash before the ruff")
safe_cash_score = game.bot_policy_score_adjustment(
  fragile_state, fragile_actor, { "card" => "JD" }, { known_hands: fragile_state[:hands] }
)
low_diamond_score = game.bot_policy_score_adjustment(
  fragile_state, fragile_actor, { "card" => "8D" }, { known_hands: fragile_state[:hands] }
)
assert(safe_cash_score - low_diamond_score >=
    GameRoomGames::Spades::EXPIRING_CONTROL_PRIORITY * 2,
  "a low diamond lead still outranks cashing the expiring top control")
fragile_replay = ReplayForPlanner.new(fragile_state, [], latest_players)
fragile_choice = game.bot_strategy.choose(
  actions: game.legal_actions(fragile_replay, fragile_actor),
  actor: fragile_actor,
  random_source: GameRoomRandom::SeededSource.new(892),
  game: game,
  replay: fragile_replay
)
assert(fragile_choice["card"] != "8D",
  "the complete bot still wastes its one safe diamond cash by leading 8D")

# Table 130, round 7 had the same correlated-control error with A-K-Q-J of
# hearts and a doubleton opponent holding many spades. Exactly two hearts can
# be cashed before the run becomes exposed, not all four.
doubleton_actor = "bot:130:2"
doubleton_hand = %w[5D 6H 8C 3H 9C TC KH QH 2H JH JD 2D QS 3S 8S AH 5S]
doubleton_remaining = game.send(:deck_for, 3) - doubleton_hand
short_hearts = %w[TH 9H]
doubleton_trump = "AS"
doubleton_short_hand = short_hearts + [doubleton_trump] + doubleton_remaining.reject do |card|
  card.end_with?("H") || short_hearts.include?(card) || card == doubleton_trump
end.first(14)
doubleton_other_hand = doubleton_remaining - doubleton_short_hand
doubleton_state = Marshal.load(Marshal.dump(fragile_state))
doubleton_state[:current_player] = doubleton_actor
doubleton_state[:hands] = {
  "papierek" => doubleton_short_hand,
  fragile_actor => doubleton_other_hand,
  doubleton_actor => doubleton_hand
}
heart_profile = game.send(
  :exact_side_suit_control_profile, doubleton_state, doubleton_actor
).fetch("H")
assert(heart_profile[:control_cards] == %w[AH KH QH JH],
  "the exact control model did not find the A-K-Q-J heart run")
assert(heart_profile[:safe_controls] == 2 && heart_profile[:threatened_controls] == 2,
  "a doubleton opponent did not limit four heart controls to two safe cashes")

# Table 130, round 2: AC had already won the trick, yet Computer 2 threw KC
# instead of 9C or TC. Once AC is on the table, KC is the promoted club winner
# and must be preserved while the contract still needs tricks.
discard_actor = "bot:130:2"
discard_state = {
  players: latest_players,
  options: latest_options.dup,
  units: latest_players,
  scores: { "papierek" => 43, fragile_actor => -70, discard_actor => 50 },
  round: 2,
  dealer_index: 0,
  bids: { fragile_actor => 8, discard_actor => 3, "papierek" => 6 },
  tricks: latest_players.each_with_object({}) { |player, tricks| tricks[player] = 0 },
  hands: {
    "papierek" => %w[7C 6S TD KD 3H AH 3S QC JH 2S 5C 8D 4S QS JC 4H 8S],
    fragile_actor => %w[6C 8C AS 7S 9D JD TH KH 4C 3C TS 5H QH AD 5S 7D],
    discard_actor => %w[8H 9H 2H KS 4D KC 9S 6D JS 7H TC 3D 2D 5D 6H QD 9C]
  },
  current_trick: [{ player: fragile_actor, card: "AC" }],
  current_player: discard_actor,
  spades_broken: false,
  phase: :playing,
  winner: nil
}
discard_context = {
  omniscient: true,
  known_hands: discard_state[:hands],
  played_cards: ["AC"]
}
assert(game.bot_future_control_discard?(discard_state, discard_actor, "KC", discard_context),
  "throwing the promoted KC under AC was not detected")
assert(!game.bot_future_control_discard?(discard_state, discard_actor, "9C", discard_context),
  "the cheap 9C discard was incorrectly protected as a future control")
discard_replay = ReplayForPlanner.new(discard_state, [], latest_players)
discard_choice = game.bot_strategy.choose(
  actions: game.legal_actions(discard_replay, discard_actor),
  actor: discard_actor,
  random_source: GameRoomRandom::SeededSource.new(893),
  game: game,
  replay: discard_replay
)
assert(discard_choice["card"] != "KC",
  "the complete bot still throws KC under AC instead of preserving it")

# Table 133, round 5 exposed the same future-control loss one seat earlier.
# QH temporarily leads over JH, but the omniscient bot knows that the last
# player can cover with KH. Ducking cheaply removes KH and promotes QH for a
# later trick, so the conservation rule must look through the unfinished trick.
second_seat_players = ["papierek", "bot:133:1", "bot:133:2"]
second_seat_actor = "bot:133:2"
second_seat_state = {
  players: second_seat_players,
  options: latest_options.dup,
  units: second_seat_players,
  scores: { "papierek" => 82, "bot:133:1" => 193, second_seat_actor => 242 },
  round: 5,
  dealer_index: 1,
  bids: { "bot:133:1" => 5, second_seat_actor => 6, "papierek" => 5 },
  tricks: { "papierek" => 0, "bot:133:1" => 1, second_seat_actor => 0 },
  hands: {
    "papierek" => %w[AS 7D 3H 6C TD 8S 9D JS 4C KH 6D 5S QD 7S 4H 9H],
    "bot:133:1" => %w[JC QC 6S 5C 8D 7H TS AD 4D 5H 4S 3S 8H TC QS],
    second_seat_actor => %w[8C 2H 5D 9S 3D JD 7C 2S TH QH KS 6H AH 2D KD KC]
  },
  current_trick: [{ player: "bot:133:1", card: "JH" }],
  current_player: second_seat_actor,
  spades_broken: false,
  phase: :playing,
  winner: nil
}
second_seat_context = {
  omniscient: true,
  known_hands: second_seat_state[:hands],
  played_cards: %w[AC 3C 9C JH]
}
assert(game.bot_future_control_discard?(
  second_seat_state, second_seat_actor, "QH", second_seat_context
), "QH was not protected from the known KH in the last seat")
assert(!game.bot_future_control_discard?(
  second_seat_state, second_seat_actor, "2H", second_seat_context
), "the cheap heart duck was incorrectly protected")
second_seat_replay = ReplayForPlanner.new(second_seat_state, [], second_seat_players)
second_seat_choice = game.bot_strategy.choose(
  actions: game.legal_actions(second_seat_replay, second_seat_actor),
  actor: second_seat_actor,
  random_source: GameRoomRandom::SeededSource.new(897),
  game: game,
  replay: second_seat_replay
)
assert(second_seat_choice["card"] != "QH",
  "the complete bot still covers JH with QH in front of the known KH")

# Live build-85 regressions, table 131. The first failed contract was selected
# from a complete-round rollout even though the calibrated estimate was below
# four and the hand's unsupported low trump could not create a fifth winner.
# In the next round the original threat audit correctly rejected six, but it
# did not audit five again; that fallback still relied on both an exposed club
# control and low trump dominated by a much longer hostile holding.
latest_bid_players = ["papierek", "bot:131:1", "bot:131:2"]
latest_bid_options = {
  "score_limit" => 300,
  "team_size" => 0,
  "no_hell" => false,
  "quicksand" => false,
  "suicide" => false,
  "omniscient_bots" => true
}
round_two_bid_state = {
  players: latest_bid_players,
  options: latest_bid_options.dup,
  units: latest_bid_players,
  scores: { "papierek" => 40, "bot:131:1" => 110, "bot:131:2" => 21 },
  round: 2,
  dealer_index: 1,
  bids: {},
  tricks: latest_bid_players.each_with_object({}) { |player, tricks| tricks[player] = 0 },
  hands: {
    "papierek" => %w[7S 8D 3S KD KH 8H KC 9D 2H 6C 5H 7D 6D 6H QD 6S TD],
    "bot:131:1" => %w[TS 8C 3H AH JS 3C 2D 4S 9S AD QS TC 5C JD AS 5S JH],
    "bot:131:2" => %w[QC 8S TH 9H JC KS 2S 3D 9C QH 4D AC 7C 4C 7H 4H 5D]
  },
  current_trick: [],
  current_player: "bot:131:2",
  spades_broken: false,
  phase: :bidding,
  winner: nil
}
round_three_bid_state = {
  players: latest_bid_players,
  options: latest_bid_options.dup,
  units: latest_bid_players,
  scores: { "papierek" => 81, "bot:131:1" => 190, "bot:131:2" => -29 },
  round: 3,
  dealer_index: 2,
  bids: { "papierek" => 1, "bot:131:1" => 10 },
  tricks: latest_bid_players.each_with_object({}) { |player, tricks| tricks[player] = 0 },
  hands: {
    "papierek" => %w[TD 5C QC 5H JH JC 7D 8H 4D 3H QD 8D TC QH 7H 6H 7C],
    "bot:131:1" => %w[KH JS JD 2S 4S QS 8C AD 4H KS 9D 9S 6S 5S 3D TS TH],
    "bot:131:2" => %w[9C 8S 5D 2D KC 3C 2H 6D 6C 9H AC AH 4C 3S 7S AS KD]
  },
  current_trick: [],
  current_player: "bot:131:2",
  spades_broken: false,
  phase: :bidding,
  winner: nil
}
[
  [round_two_bid_state, 894],
  [round_three_bid_state, 895]
].each do |bid_state, seed|
  bid_replay = ReplayForPlanner.new(bid_state, [], latest_bid_players)
  bid_context = game.bot_decision_context(bid_replay, "bot:131:2").fetch(:bid_threat)
  expected_risky_bids = bid_state[:round] == 2 ? [5] : [5, 6]
  audited_fallbacks = bid_context.fetch(:bid_pressures).keys.select do |bid|
    bid <= bid_context.fetch(:planned_bid)
  end.sort
  assert(audited_fallbacks == expected_risky_bids,
    "round #{bid_state[:round]} audited #{audited_fallbacks} instead of #{expected_risky_bids}")
  bid_choice = game.bot_strategy.choose(
    actions: game.legal_actions(bid_replay, "bot:131:2"),
    actor: "bot:131:2",
    random_source: GameRoomRandom::SeededSource.new(seed),
    game: game,
    replay: bid_replay
  )
  assert(bid_choice["bid"] == 4,
    "the cascading threat audit still chose #{bid_choice['bid']} instead of four in round #{bid_state[:round]}")
end

strong_bid_one = %w[AC 6S AS JH QH QS 2H 5D AD AH 8S 9D 7C JC JS QD TH]
strong_bid_two = %w[4D KH 2S 7H JD 5S 3H TD 6D 9H 7S 8H 3S 2D 7D 4S 5C]
strong_bid_state = Marshal.load(Marshal.dump(round_two_bid_state))
strong_bid_state[:round] = 1
strong_bid_state[:dealer_index] = 0
strong_bid_state[:scores] = latest_bid_players.each_with_object({}) { |player, scores| scores[player] = 0 }
strong_bid_state[:current_player] = "bot:131:1"
strong_bid_state[:hands] = {
  "papierek" => game.send(:deck_for, 3) - strong_bid_one - strong_bid_two,
  "bot:131:1" => strong_bid_one,
  "bot:131:2" => strong_bid_two
}
strong_bid_replay = ReplayForPlanner.new(strong_bid_state, [], latest_bid_players)
strong_bid_choice = game.bot_strategy.choose(
  actions: game.legal_actions(strong_bid_replay, "bot:131:1"),
  actor: "bot:131:1",
  random_source: GameRoomRandom::SeededSource.new(896),
  game: game,
  replay: strong_bid_replay
)
assert(strong_bid_choice["bid"] == 10,
  "the cascading threat audit reduced the robust ten-trick hand to #{strong_bid_choice['bid']}")

# Table 133, round 6: both nine and ten were projected to win the match from
# 244 points. Nine is the safer declaration and still crosses 300, while ten
# can lose one hundred points when the marginal TH is not promoted.
closing_players = ["papierek", "bot:133:1", "bot:133:2"]
closing_actor = "bot:133:1"
closing_state = {
  players: closing_players,
  options: latest_bid_options.dup,
  units: closing_players,
  scores: { "papierek" => 133, closing_actor => 244, "bot:133:2" => 182 },
  round: 6,
  dealer_index: 2,
  bids: { "bot:133:2" => 3, "papierek" => 3 },
  tricks: closing_players.each_with_object({}) { |player, tricks| tricks[player] = 0 },
  hands: {
    "papierek" => %w[5C AC JH 2S 9D KD 8H 2D 9C 8D 7S QD 9H 5H 4S 6S 5D],
    closing_actor => %w[QS 4D TH AH 7D 6C KC 4C QC KS 6D JS TS AS 4H 7H 5S],
    "bot:133:2" => %w[AD JC 9S 3H 3C 8C QH 2H 3D TC 3S JD TD 8S 7C KH 6H]
  },
  current_trick: [],
  current_player: closing_actor,
  spades_broken: false,
  phase: :bidding,
  winner: nil
}
closing_replay = ReplayForPlanner.new(closing_state, [], closing_players)
closing_choice = game.bot_strategy.choose(
  actions: game.legal_actions(closing_replay, closing_actor),
  actor: closing_actor,
  random_source: GameRoomRandom::SeededSource.new(898),
  game: game,
  replay: closing_replay
)
assert(closing_choice["bid"] == 9,
  "the match-closing bot still risks ten instead of the winning bid of nine")

# The same decision must not depend on acting last. The round plan already
# projects both declarations as wins, while own-score arithmetic proves that
# nine crosses the target; an opponent who has not bid yet does not change it.
early_closing_state = Marshal.load(Marshal.dump(closing_state))
early_closing_state[:bids].delete("papierek")
early_closing_adjustment = game.send(
  :bot_match_closing_bid_score_adjustment,
  early_closing_state,
  closing_actor,
  10,
  game.bot_decision_context(closing_replay, closing_actor)
)
assert(early_closing_adjustment < 0.0,
  "the match-closing guard still waits for every opponent to bid")

# At nine existing bags, lowering ten to nine would turn the tenth trick into
# the bag that triggers a 100-point penalty. In that case the safer-looking
# declaration no longer closes the match and must not be forced.
closing_context = game.bot_decision_context(closing_replay, closing_actor)
bag_hazard_state = Marshal.load(Marshal.dump(closing_state))
bag_hazard_state[:scores][closing_actor] = 249
bag_hazard_adjustment = game.send(
  :bot_match_closing_bid_score_adjustment,
  bag_hazard_state,
  closing_actor,
  10,
  closing_context
)
assert(bag_hazard_adjustment == 0.0,
  "the match-closing guard ignored the losing tenth-bag penalty")

round_environment = GameRoomSimulation::Environment.new_game(
  game: game,
  players: GameRoomParticipants.bots_for(901, 3),
  options: { "score_limit" => 300, "team_size" => 0, "omniscient_bots" => false },
  seed: 1941
)
round_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
actions = 0
initial_round = round_environment.replay.state[:round]
until round_environment.replay.state[:round] > initial_round
  round_actor = round_environment.active_actor
  round_actions = round_environment.legal_actions(round_actor)
  selected = GameRoomBots.choose(game.bot_strategy, {
    actions: round_actions,
    observation: round_environment.observation(round_actor),
    actor: round_actor,
    random_source: round_environment.random_source,
    game: game,
    replay: round_environment.replay,
    context: round_environment.context,
    simulation: round_environment
  })
  assert(selected != nil, "the planner stopped a complete round")
  assert(round_environment.step(selected, actor: round_actor) == :ok,
    "the planner selected an illegal action")
  actions += 1
  assert(actions < 100, "the planned Spades round did not terminate")
end
round_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - round_started

puts "Spades round planner tests passed; observed bid #{elapsed.round(3)}s, " \
  "complete fair round #{round_elapsed.round(3)}s"
