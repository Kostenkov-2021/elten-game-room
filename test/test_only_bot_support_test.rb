require_relative '../lib/game_random'
require_relative '../lib/bot_turn_gate'

def assert(value, message)
  raise message unless value
end

assert(!GameRoomRandom.const_defined?(:SequenceSource, false), 'test sequence leaked into runtime')
assert(!GameRoomBots.const_defined?(:TurnGate, false), 'legacy test pacing leaked into runtime')
require_relative 'support/sequence_random'
require_relative 'support/legacy_turn_gate'

values = [6, 1, 4]
source = GameRoomRandom::SequenceSource.new(values)
roll = source.roll(count: 3, sides: 6)
assert(roll.values == values && roll.source == 'test_sequence', 'sequence behavior changed')
assert(values == [6, 1, 4], 'sequence mutates caller input')
begin
  source.roll(count: 1, sides: 6)
  raise 'exhausted sequence did not fail'
rescue RangeError
end
begin
  GameRoomRandom::SequenceSource.new([7]).roll(count: 1, sides: 6)
  raise 'out-of-range sequence value accepted'
rescue RangeError
end
now = 0.0
gate = GameRoomBots::TurnGate.new(clock: -> { now })
lease = gate.acquire
assert(lease && !gate.ready? && !gate.acquire, 'legacy gate allows simultaneous moves')
gate.release(Object.new, attempted: true)
assert(!gate.ready?, 'foreign lease releases gate')
gate.release(lease, attempted: true)
assert(!gate.ready?, 'legacy cooldown missing')
now = 1.0
assert(gate.ready?, 'legacy gate remains blocked')
assert(GameRoomBots.const_defined?(:TurnController, false), 'active controller disappeared')
require_relative '../lib/spades_learning'
%i[TrainingReport Evaluation CampaignReport Scenario ScenarioMatrix].each do |name|
  assert(!SpadesLearning.const_defined?(name, false), "training-only #{name} leaked into Spades runtime")
end
assert(SpadesLearning.const_defined?(:Policy, false), 'runtime Spades policy disappeared')
puts 'Test-only sequence and legacy pacing moved without changing their behavior; runtime exposes neither'
