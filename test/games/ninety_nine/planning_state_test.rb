require_relative '../../../games/ninety_nine'
require_relative '../../../lib/game_simulation'
require_relative '../../support/assertions'
include GameRoomTest::Assertions

def rejects_mutation(message)
  begin
    yield
  rescue FrozenError
    return
  end
  raise message
end

game = GameRoomGames::NinetyNine.new
env = GameRoomSimulation::Environment.new_game(game: game, players: %w[Alice Bob Carol Dave], seed: 137)
source = env.replay.state
before = Marshal.dump(source)
[false, true].each do |omniscient|
  sampler = NinetyNinePlanning::WorldSampler.new(game, source, source[:current_player], omniscient: omniscient)
  world = sampler.sample(0)
  other = sampler.sample(1)
  actor = world[:current_player]
  original = Marshal.dump(world)
  sibling = world.fork
  branch = world.fork
  branch[:tokens][actor] = -100
  branch[:eliminated][actor] = true
  branch[:hands][actor].clear
  branch[:draw_pile].clear
  branch[:discard] << 'local'
  assert(Marshal.dump(world) == original, 'branch mutated its sampled world')
  assert(sibling == world, 'branch mutated its sibling')
  assert(other[:tokens][actor] >= 0 && !other[:hands][actor].empty?, 'branch mutated another sampled world')
  rejects_mutation('shared player name is mutable') { sibling[:players].first << 'changed' }
  rejects_mutation('shared player list is mutable') { sibling[:players].clear }
  rejects_mutation('shared options are mutable') { sibling[:options]['starting_tokens'] = 1 }
  rejects_mutation('shared card is mutable') { sibling[:hands][actor].first << 'changed' }

  actions = world[:hands][actor].flat_map { |card| game.send(:card_play_actions, card, world[:total]) }
  actions.each do |action|
    after = NinetyNinePlanning::Transition.play(game, world, actor, action)
    assert(after && Marshal.dump(world) == original, 'transition changed its source')
    rejects_mutation('transition introduced a mutable card') { after[:discard].last << 'changed' }
    assert(after[:hands][actor].length == world[:hands][actor].length, 'replacement draw changed hand size')
    # Feed an ordinary Hash too: callers outside the search must still receive
    # an owned state, without freezing or borrowing their model.
    plain = Marshal.load(Marshal.dump(world)).to_h
    plain_before = Marshal.dump(plain)
    assert(NinetyNinePlanning::Transition.play(game, plain, actor, action) == after, 'ordinary input transition differs')
    assert(Marshal.dump(plain) == plain_before && !plain[:players].frozen?, 'ordinary input was modified/frozen')
  end
end
assert(Marshal.dump(source) == before && !source[:hands].frozen?, 'sampling changed/froze live replay')

# Recycling must own the reordered containers and retain an immutable top.
raw = game.send(:initial_state, %w[Alice Bob Carol], game.default_options)
raw.merge!(phase: :playing, current_player: 'Alice', total: 20, draw_pile: [],
  discard: %w[03C 05C 06C], planning_seed: 817, planning_recycles: 2)
raw[:hands]['Alice'] = %w[09C 04C 0AC]
world = NinetyNinePlanning::State.from(raw)
before = Marshal.dump(world)
action = {'card' => '09C|normal'}
first = NinetyNinePlanning::Transition.play(game, world, 'Alice', action)
second = NinetyNinePlanning::Transition.play(game, world, 'Alice', action)
assert(first == second && first[:planning_recycles] == 3, 'recycling changed deterministic planning order')
assert(first[:discard] == ['09C'] && first[:draw_pile].length == 2, 'recycling lost cards/top')
first[:draw_pile].clear
first[:hands]['Alice'].clear
assert(second[:draw_pile].length == 2 && Marshal.dump(world) == before, 'recycling shares mutable branches')

# Terminal branches update tokens/elimination without mutating the ancestor.
raw[:tokens] = raw[:players].to_h { |player| [player, 0] }
raw[:total] = 98
raw[:hands]['Alice'] = ['0AC']
world = NinetyNinePlanning::State.from(raw)
after = NinetyNinePlanning::Transition.play(game, world, 'Alice', {'card' => '0AC|one'})
assert(after[:winner] == 'Alice' && after[:phase] == :finished, 'terminal branch failed')
assert(world[:eliminated].values.none? && world[:winner].nil?, 'terminal branch mutated ancestor')
puts 'PASS Ninety-nine planning: owned worlds, immutable leaves, isolated branches, recycling, elimination and terminal states'
