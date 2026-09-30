require_relative "../../support/elten_array_shuffle"
require_relative "../../support/ui"
require_relative "../../../games/scientific_war"
require_relative "../../../lib/game_random"

def assert(value, message)
  raise message unless value
end

GAME = GameRoomGames::ScientificWar.new
ACTOR = "Alice"

def fixture(hand, others = { "Bob" => %w[AS1 4S1] }, phase: :spying, pile: [], reversed: false, trick: 1, carried: [])
  players = [ACTOR, *others.keys]
  state = GAME.send(:initial_state, players, GAME.default_options)
  state[:hands] = others.merge(ACTOR => hand)
  state[:piles][ACTOR] = pile
  state.update(phase: phase, reversed: reversed, trick: trick, carried: carried)
  if phase == :spying
    state[:powers][ACTOR] = "Q"
    state[:reveals] = others.transform_values(&:first)
  end
  GameRoomGames::Replay.new(players: players, state: state, history: [], accepted_events: [], current_player: phase == :spying ? ACTOR : nil)
end

def choose(replay, seed: 1, random: nil)
  GAME.bot_strategy.choose(actions: GAME.legal_actions(replay, ACTOR), actor: ACTOR,
    random_source: random || GameRoomRandom::SeededSource.new(seed), game: GAME, replay: replay)
end

def rank(action)
  action["card"].to_s[0]
end

assert(!GAME.bot_strategy.simulation_required?, "the bounded policy requested a complete simulator")
assert(rank(choose(fixture(%w[2H1 X1]))) == "X", "the spy discarded a losing two instead of forcing a war")
assert(rank(choose(fixture(%w[JH1 KH1 2H1]))) == "J", "the spy missed the immediate jack revolution against an ace")
assert(rank(choose(fixture(%w[JH1 2H1 KH1], { "Bob" => %w[JS1 4S1] }))) == "2", "two jacks cancelling was mistaken for a winning revolution")
assert(rank(choose(fixture(%w[AH1 KH1], { "Bob" => %w[QS1 4S1] }))) == "K", "the spy spent an ace where a king also wins")
assert(rank(choose(fixture(%w[3H1 4H1], { "Bob" => %w[5S1 AS1] }, reversed: true))) == "4", "the spy did not conserve the stronger low card during a revolution")
assert(rank(choose(fixture(%w[X1 KH1], { "Bob" => %w[AS1 4S1], "Carol" => %w[AD1 5D1] }))) == "X", "the joker failed to capture equal highest cards")
assert(rank(choose(fixture(%w[X1 2H1], { "Bob" => %w[X2 4S1], "Carol" => %w[AD1 5D1] }))) == "2", "the spy ignored cancellation of multiple jokers")
assert(rank(choose(fixture(%w[X1 2H1], trick: 50))) == "X", "the final trick preferred a loss over a joker draw")
assert(rank(choose(fixture(%w[X1 AH1], { "Bob" => %w[KS1 4S1 5S1] }, trick: 50))) == "A", "the final trick forced a pointless losing war instead of winning the pot")
assert(rank(choose(fixture(%w[X1 2H1], { "Bob" => %w[AS1] }))) == "X", "the spy missed the win by leaving its last opponent without cards")

weak_pile = fixture(%w[AH1 KH1], phase: :choosing, pile: %w[2H1 3H1 4H1 5H1])
weak_pile.state[:powers][ACTOR] = "8"
20.times { |seed| assert(choose(weak_pile, seed: seed)["action"] != "swap", "a larger but weak pile displaced the useful hand") }
strong_pile = fixture(%w[2H1 3H1 4H1], phase: :choosing, pile: %w[AH1])
strong_pile.state[:powers][ACTOR] = "8"
assert(choose(strong_pile)["action"] == "swap", "the smaller pile's useful ace was ignored")

# Knowledge firewall: opponents' containers allow only their public counts.
# Neither the hidden context nor private commitment bytes may enter the policy.
class CountOnlyCards
  def initialize(length)
    @length = length
  end

  def length
    @length
  end

  def method_missing(name, *)
    raise "read opponent cards via #{name}"
  end
end

private_a = fixture(%w[2H1 8H1 QH1 AH1 X1], { "Bob" => %w[AS1 2S1 5S1], "Carol" => %w[JD1 KD1 4D1] }, phase: :choosing)
private_b = Marshal.load(Marshal.dump(private_a))
private_a.state[:commits] = { "Bob" => "first private digest" }
private_b.state[:commits] = { "Bob" => "different private digest" }
private_b.state[:reveals] = { "Bob" => "secret bogus current reveal" }
%w[Bob Carol].each do |player|
  private_b.state[:hands][player] = CountOnlyCards.new(1)
  private_b.state[:piles][player] = CountOnlyCards.new(2)
end
frozen_before = Marshal.dump(private_a)
30.times do |seed|
  first_rng = GameRoomRandom::SeededSource.new(seed)
  second_rng = GameRoomRandom::SeededSource.new(seed)
  first = choose(private_a, random: first_rng)
  second = choose(private_b, random: second_rng)
  assert(first == second, "private hand/pile distribution or current reveal changed an ordinary choice")
  assert(first_rng.roll(count: 4, sides: 256).values == second_rng.roll(count: 4, sides: 256).values, "private state changed RNG consumption")
end
assert(Marshal.dump(private_a) == frozen_before, "evaluation mutated the replay")
assert(GAME.bot_action_score(private_a, ACTOR, GAME.legal_actions(private_a, ACTOR).first).finite?, "the scoring contract no longer works")

dead = fixture(%w[2H1 AH1 X1], { "Bob" => %w[AS1 2S1], "Carol" => [] }, phase: :choosing)
dead.state[:eliminated]["Carol"] = true
dead.state[:hands]["Carol"] = Object.new
dead.state[:piles]["Carol"] = Object.new
assert(GAME.legal_actions(dead, ACTOR).include?(choose(dead)), "eliminated seats participated in analysis")

# All ranks, both orientations, against a revealed single card: whenever a
# sure win is available the spy must choose one, including jack/joker effects.
checked = 0
%w[2 3 4 5 6 7 8 9 T J Q K A X].each do |opponent|
  [false, true].each do |reversed|
    replay = fixture(%w[2H1 5H1 8H1 JH1 QH1 KH1 AH1 X1], { "Bob" => ["#{opponent}S1", "4S1"] }, reversed: reversed)
    actions = GAME.legal_actions(replay, ACTOR)
    wins = actions.select do |action|
      GAME.send(:trick_outcome, replay.state, replay.state[:reveals].merge(ACTOR => action["card"])).first == ACTOR
    end
    next if wins.empty?

    assert(wins.include?(choose(replay)), "the spy missed a sure win against #{opponent}, reversed=#{reversed}")
    checked += 1
  end
end
puts "PASS Scientific War bot: #{checked} exact spy win positions; joker denial/cancellation, revolution, card conservation, final draw, elimination, quality-aware swap, private-state firewall and repeatable RNG"
