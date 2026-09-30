require_relative "../../../lib/game_simulation"
require_relative "../../../games/spades"

def assert(value, message)
  raise message unless value
end

def copy(value)
  Marshal.load(Marshal.dump(value))
end

def scoring_calls
  count = 0
  trace = TracePoint.new(:call) do |event|
    count += 1 if event.defined_class == GameRoomGames::Spades::Scoring && event.method_id == :apply
  end
  result = trace.enable { yield }
  [result, count]
end

# Former independent-per-player evaluation, retained only as a regression
# reference. It shares the unchanged utility formula, not its new batched path.
class SeparateScoringPlanner < SpadesPlanning::RoundPlanner
  private
  def terminal_utilities(state)
    state[:players].to_h { |player| [player_key(state, player), terminal_utility(state, player)] }
  end
end

game = GameRoomGames::Spades.new
[[3,0,false],[4,0,false],[4,2,false],[5,0,false],[6,0,false],[6,2,false],[4,2,true]].each do |count, team, quicksand|
  ps = Array.new(count) { |i| "P#{i}" }
  options = game.normalize_options('team_size' => team, 'quicksand' => quicksand)
  scoring = GameRoomGames::Spades::Scoring.new(ps, options)
  state = {players: ps, options: options, scores: scoring.unit_ids.to_h { |p| [p,109] },
    bids: ps.to_h { |p| [p,1] }, tricks: ps.each_with_index.to_h { |p,i| [p,i+1] }}
  before = Marshal.dump(state)
  expected = SeparateScoringPlanner.new(game).send(:terminal_utilities, state)
  actual, calls = scoring_calls { SpadesPlanning::RoundPlanner.new(game).send(:terminal_utilities, state) }
  assert(actual == expected, "terminal utility changed: #{[count, team, quicksand]}")
  assert(calls == 1, 'terminal leaf scores the same round repeatedly')
  assert(Marshal.dump(state) == before, 'scoring mutates state')
end

ps = %w[A B C]
tail = {players: ps, options: game.normalize_options({}), scores: ps.to_h { |p| [p,0] }, bids: ps.to_h { |p| [p,1] },
  tricks: ps.to_h { |p| [p,5] }, hands: {'A' => ['3H'], 'B' => ['4H'], 'C' => ['5H']}, current_trick: [],
  current_player: 'A', phase: :playing, spades_broken: true}
exact, exact_calls = scoring_calls { SpadesPlanning::RoundPlanner.new(game).send(:exact_utilities, copy(tail), {}) }
value, calls = scoring_calls { SpadesPlanning::RoundPlanner.new(game).send(:play_round, copy(tail), 'A', 0) }
assert(exact_calls == 1 && calls == 1 && value == exact.fetch('A'), 'exact rollout eagerly scores a fallback')
4.times do |variant|
  value = SpadesPlanning::RoundPlanner.new(game).send(:play_round, copy(tail), 'A', variant, exact_limit: 0)
  assert(value == exact.fetch('A'), "deterministic rollout changed: #{variant}")
end

# Deck order and subsequent RNG match the old constructor for all deck sizes.
{3 => 1, 4 => 0, 5 => 2, 6 => 4}.each do |count, removed|
  expected = GameRoomGames::Spades::SUITS.product(GameRoomGames::Spades::RANKS).map { |suit, rank| "#{rank}#{suit}" }
  GameRoomGames::Spades::SUITS.first(removed).each { |suit| expected.delete("2#{suit}") }
  actual = game.send(:deck_for, count)
  assert(actual == expected && !actual.frozen?, 'deck content/order/mutability changed')
  assert(game.send(:cards_per_player, count) == expected.length / count, 'hand size changed')
  [-1, 0, 71, 2**63].each do |seed|
    old_rng, new_rng = Random.new(seed), Random.new(seed)
    assert(GameRoomRandom.shuffle(actual, random: new_rng) == GameRoomRandom.shuffle(expected, random: old_rng), 'shuffle changed')
    assert(new_rng.rand == old_rng.rand, 'shuffle RNG changed')
  end
  actual.pop
  assert(game.send(:deck_for, count) == expected, 'deal array leaked into the template')
end

# Compare full normal fair-planner contexts, including refinement and weights.
# A classic freshly allocated deck is used on the reference side as well.
reference_game = GameRoomGames::Spades.new
def reference_game.deck_for(count)
  cards = self.class::SUITS.product(self.class::RANKS).map { |suit, rank| "#{rank}#{suit}" }
  self.class::SUITS.first({3 => 1, 4 => 0, 5 => 2, 6 => 4}.fetch(count)).each { |suit| cards.delete("2#{suit}") }
  cards
end
def reference_game.spades_round_planner
  @spades_round_planner ||= SeparateScoringPlanner.new(self)
end
env = GameRoomSimulation::Environment.new_game(game: game, players: ps, seed: 71)
while env.replay.state[:phase] == :bidding
  actor = env.active_actor
  bid = env.legal_actions(actor).find { |action| action['bid'] == 1 } || env.legal_actions(actor).first
  assert(env.step(bid, actor: actor) == :ok, 'bid setup rejected')
end
actual = game.bot_decision_context(env.replay, env.active_actor)
expected = reference_game.bot_decision_context(env.replay, env.active_actor)
assert(actual == expected, 'full planner context changed')
assert(game.send(:spades_round_planner).last_failure.nil?, 'normal planner fell back')
source, reference_source = GameRoomRandom::SeededSource.new(19), GameRoomRandom::SeededSource.new(19)
arguments = {actions: env.legal_actions, actor: env.active_actor, replay: env.replay}
choice = game.bot_strategy.choose(**arguments, game: game, random_source: source)
reference_choice = reference_game.bot_strategy.choose(**arguments, game: reference_game, random_source: reference_source)
assert(choice == reference_choice, 'strategy choice differs from the separate-scoring/classic-deck reference')
assert(source.roll(count: 8, sides: 6).values == reference_source.roll(count: 8, sides: 6).values, 'strategy RNG consumption changed')
puts 'Spades efficiency: 7 scoring variants, exact/4 rollout tails, 16 deck/RNG comparisons, equal full fair context and strategy/RNG'
