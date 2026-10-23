require_relative '../support/binary_rules_load' if ARGV.first
require_relative '../support/assertions'
require_relative '../../lib/tournaments/server_phase_plan'
include GameRoomTest::Assertions
T = GameRoomTournaments

seeds = %w[alice bob carol dave eve frank grace heidi]
base = T::KnockoutRound.build(seeds: seeds, players_per_match: 2, round_number: 1)
plan = T::KnockoutWinSeries.build(base: base, history: [], target: 99, attempt: 1)
metadata = plan.slice('round', 'seeds', 'players_per_match', 'generation', 'series').merge(
  'phase_digest' => 'c' * 64, 'parent_plan_digest' => 'd' * 64)
generation = 'a' * 64
schedule, matches = T::KnockoutSchedule.matches(metadata: metadata, generation: generation)
candidate = {'schedule_id' => schedule, 'publication_digest' => 'b' * 64,
  'roster_generation' => generation, 'publication_ref' => {'author' => 'alice', 'publication_key' => 'capacity'},
  'format' => 'knockout', 'roster' => seeds, 'matches' => matches, 'knockout' => metadata,
  'knockout_wins_to' => 99, 'final_wins_to' => 99, 'knockout_rematch' => false, 'final_rematch' => false}
receipts_for = ->(value) do
  value.fetch('matches').map do |match|
    {'match_id' => match['match_id'], 'leg' => match['leg'], 'summary' => {
      'participants' => match['players'].sort, 'winners' => [match['players'].first],
      'scores' => nil, 'draw' => false, 'event_count' => 5}}
  end
end
normalized = ->(receipts) do
  receipts.map { |row| row.fetch('summary').slice('participants', 'winners', 'scores').merge(
    'id' => JSON.generate([row['match_id'], row['leg']])) }
end

# Generate every predecessor using the production planner, not a patched
# history. These are sporting-result fixtures, not 396 played native games.
99.times do |index|
  receipts = receipts_for.call(candidate)
  rows = normalized.call(receipts)
  if index == 64
    partial = T::KnockoutStandings.calculate(candidate: candidate, units: seeds,
      results: rows.take(1), unit_key: 'players')
    assert_equal(257, partial.fetch('series_history').size)
    assert_equal('awaiting_series', partial.fetch('knockout_state'))
    assert_equal([64, 64, 64, 65], partial.fetch('series_progress').map { |pair| pair['wins'].values.max }.sort)
  end
  view = T::KnockoutStandings.calculate(candidate: candidate, units: seeds, results: rows, unit_key: 'players')
  assert_equal(index == 98 ? 'ready_next_round' : 'awaiting_series', view.fetch('knockout_state'))
  assert_equal([index + 1] * 4, view.fetch('series_progress').map { |pair| pair['wins'].values.max })
  candidate = T::ServerPhasePlan.build(candidate: candidate, results: receipts).fetch('candidate')
  if index == 64
    @capacity_history = view.fetch('series_history')
    assert_equal(260, @capacity_history.size)
  end
end
assert_equal(2, candidate.dig('knockout', 'round'))
assert_equal(4, candidate.fetch('roster').size)
assert_equal(1, candidate.dig('knockout', 'series', 'attempt'))
assert_equal([], candidate.dig('knockout', 'series', 'history'))

history = @capacity_history
original = Marshal.dump(history)
project = ->(rows) { T::KnockoutWinSeries.progress(base: base, history: rows, target: 99) }
assert(project.call(history).frozen?)
copy = T::Standings.validated_results(units: seeds, results: history, max_results: 4096)
copy.first.fetch('participants') << 'changed-copy'
assert_equal(original, Marshal.dump(history), 'Validation mutated the published history')

# Keep the ordinary phase limit and every global validation invariant.
assert_raises(T::Publication::Invalid) { T::Standings.calculate(units: seeds, results: history) }
duplicate = history.map(&:dup)
duplicate[1]['id'] = duplicate[0]['id'] # Same identity in a different pairing.
assert_raises(T::Publication::Invalid) { project.call(duplicate) }
mixed_order = history.map(&:dup)
mixed_order.take(2).each_with_index do |row, index|
  row['scores'] = row['participants'].to_h { |unit| [unit, 1] }
  row['score_order'] = index.zero? ? 'higher' : 'lower'
end
assert_raises(T::Publication::Invalid) { project.call(mixed_order) }
wrong_pair = history.map(&:dup)
wrong_pair[0] = wrong_pair[0].merge('participants' => %w[alice carol], 'winners' => ['alice'])
assert_equal(:invalid_phase_results, assert_raises(T::Publication::Invalid) { project.call(wrong_pair) }.code)
[nil, [], {'id' => 'bad', 'participants' => nil}, {'id' => 'bad', 'participants' => ['alice', 1]}].each do |bad|
  assert_raises(T::Publication::Invalid) { project.call(history + [bad]) }
end
assert_raises(T::Publication::Invalid) { project.call(Array.new(4097, history.first)) }
assert_raises(T::Publication::Invalid) do
  T::Standings.validated_results(units: seeds, results: [], max_results: 4097)
end
large = Array.new(1500) { |index| history.first.merge('id' => "#{index}-#{'x' * 200}") }
assert_equal(:json_budget, assert_raises(T::Publication::Invalid) do
  T::Standings.validated_results(units: seeds, results: large, max_results: 4096)
end.code)
ended = history.take(1) + [history.first.merge('id' => 'after-completion')]
assert_equal(:result_after_series_finished, assert_raises(T::Publication::Invalid) do
  T::KnockoutWinSeries.progress(base: base, history: ended, target: 1)
end.code)
assert_equal(original, Marshal.dump(history))
puts 'PASS knockout series capacity: 257th result, 99 generated four-pair phases, next round, unchanged bounded validation and no input mutation'
