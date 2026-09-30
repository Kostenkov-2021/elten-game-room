require_relative '../../support/room_interface'
require_relative '../../support/krowa'

def tower_view(run, replay = run.replay, viewer = 'Alice')
  run.game.game_view_spec(replay, viewer).surface.parts.to_h { |part| [part.id, part.surface] }
end

run = KrowaTestGame.new(variant: 'tower', players: %w[Alice Bob])
%w[Alice Bob Watcher].each do |viewer|
  parts = tower_view(run, run.replay, viewer)
  assert(parts['status'].value == 'Preparing the word.', 'initial waiting status absent')
  assert(!parts['results'].value.include?('Attempts this round'), 'limit shown before word exists')
end
run.automatic
assert(tower_view(run)['results'].value.include?('0 of 15'), 'three-letter limit changed')
run.guess('Alice', 'las'); run.automatic
run.guess('Bob', 'kot'); run.automatic
assert(run.replay.state[:phase] == :revealing, 'expected reveal phase')
assert(tower_view(run)['results'].value.include?('2 of 15'), 'reveal loses attempts')
run.automatic
assert(run.replay.state[:phase] == :setup, 'expected between-word phase')
text = tower_view(run)['results'].value
assert(text.include?('Completed rounds: 1.'), 'completed count lost')
assert(text.include?('1. kot: 2 attempts'), 'completed solution lost')
assert(text.include?('Preparing the word.') && !text.include?('Attempts this round'), 'previous word described as current')
run.automatic
assert(tower_view(run)['results'].value.include?('0 of 15'), 'new round attempts not reset')
run.surrender('Alice'); run.automatic
assert(run.replay.finished? && tower_view(run)['results'].value.include?('Completed rounds: 1.'), 'finished view lost rounds')

invalid = KrowaTestGame.new(variant: 'tower', players: ['Alice'])
assert(tower_view(invalid)['status'].value == 'Invalid table configuration.', 'invalid setup obscured')

# Presentation boundaries for all supported lengths, including delayed prepare.
{3 => 15, 4 => 24, 5 => 30, 6 => 42, 7 => 49, 8 => 64}.each do |length, limit|
  [:active, :revealing, :finished].each do |phase|
    replay = run.replay
    replay.state.merge!(phase: phase, length: length)
    assert(tower_view(run, replay)['results'].value.include?("of #{limit}."), "#{phase}/#{length}: wrong limit")
  end
end
replay = run.replay
replay.state.merge!(phase: :preparing, length: 0)
assert(tower_view(run, replay)['results'].value.include?('Preparing the word.'), 'delayed prepare failed')
%w[random daily race].each do |variant|
  game = KrowaTestGame.new(variant: variant, players: variant == 'race' ? %w[Alice Bob] : ['Alice'])
  tower_view(game)
  game.automatic
  tower_view(game)
end
puts 'PASS Krowa tower views: first/between words, invalid setup, reveal/finish, all limits, other variants'
