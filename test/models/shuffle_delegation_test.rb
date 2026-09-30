require_relative "../support/elten_array_shuffle"
require_relative "../../games/card_game"
require_relative "../../lib/domino_tiles"
require_relative "../../lib/game_teams"
require_relative "../../lib/ninety_nine_strategy"
require_relative "../../lib/tysiac_strategy"

def assert(condition, message)
  raise message unless condition
end

# Frozen reference to the old duplicated core. It must not call the shared
# helper: this checks order and the next RNG operation independently.
def previous_shuffle(values, random)
  result = values.to_a.dup
  (result.length - 1).downto(1) do |index|
    other = random.rand(index + 1)
    result[index], result[other] = result[other], result[index]
  end
  result
end

families = [[], ["one"], %w[a b c d], ["a", "a", "żółty", "日本語"], (1..54).to_a]
planner99 = NinetyNinePlanning::WorldSampler.allocate
planner1000 = TysiacPlanning::Planner.allocate
cases = 0
families.each do |values|
  100.times do |seed|
    [planner99, planner1000].each do |planner|
      old_random, new_random = Random.new(seed), Random.new(seed)
      frozen_input = values.dup.freeze
      expected = previous_shuffle(values, old_random)
      actual = planner.send(:deterministic_shuffle, frozen_input, new_random)
      assert(expected == actual && !actual.equal?(frozen_input), "planner order/input-copy changed")
      assert(old_random.rand(1_000_000) == new_random.rand(1_000_000), "planner advanced RNG differently")
      cases += 1
    end
  end
end

game = GameRoomGames::CardGame.new
seeds = [nil, 0, 17, "17", "00017", "ff", "FF", "deadbeef", "", "-1", " 17", "żółć"]
families.each do |values|
  seeds.each do |seed|
    text = seed.to_s
    number = text.match?(/\A[0-9a-f]+\z/i) ? text.to_i(16) : Digest::SHA256.hexdigest(text).to_i(16)
    expected = previous_shuffle(values, Random.new(number))
    assert(game.send(:shuffled_cards, values.freeze, seed) == expected, "card seed conversion changed: #{seed.inspect}")
  end
  seeds.grep(String).each do |seed|
    expected = previous_shuffle(values, Random.new(seed.to_i(16)))
    assert(GameRoomDominoTiles.shuffle(values.freeze, seed) == expected, "domino seed conversion changed: #{seed.inspect}")
  end
end

players = %w[Alice Bob Carol David Eve Frank]
100.times do |seed|
  old_random, new_random = Random.new(seed), Random.new(seed)
  expected = previous_shuffle(players, old_random)
  assignment = GameRoomTeams::Assignment.new(players: players, team_size: 2)
  assignment.move(0, 1)
  assignment.assign(0, 2)
  assert(assignment.randomize(random: new_random).equal?(assignment), "team randomization no longer returns self")
  assert(assignment.players == expected && assignment.valid?, "team randomization did not use original roster")
  assert(old_random.rand(1_000_000) == new_random.rand(1_000_000), "team RNG consumption changed")
  assignment.reset
  assert(assignment.players == players, "team reset mutated original roster")
end

100.times do |seed|
  cards = %w[C2 C3 D4 HA S9 D6 C7]
  serial = seed % 4
  state = { draw_pile: [], discard: cards + ["SK"], planning_seed: seed, planning_recycles: serial }
  number = Digest::SHA256.hexdigest([seed, serial, cards].inspect)[0, 16].to_i(16)
  expected = previous_shuffle(cards, Random.new(number))
  NinetyNinePlanning::Transition.refill_draw_pile(state)
  assert(state[:draw_pile] == expected && state[:discard] == ["SK"], "99 recycle changed sampled seed or top card")
  assert(state[:planning_recycles] == serial + 1, "99 recycle counter changed")
end

puts "PASS shared shuffle: #{cases} planner order/next-RNG cases, card/domino seed conversions, 100 team and 100 recycle cases under ELTEN override"
