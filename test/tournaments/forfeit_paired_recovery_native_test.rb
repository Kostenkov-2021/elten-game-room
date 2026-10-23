require 'timeout'
require_relative '../support/tournament_forfeit_native'
require_relative '../../lib/tournaments/server_phase_plan'
T = GameRoomTournaments

TournamentForfeitNative.with_fixture do |f|
  candidate = f.candidate
  metadata = T::KnockoutSchedule.direct_metadata(seeds: candidate['roster'], generation: candidate['roster_generation'],
    publication_digest: candidate['publication_digest'], rematch: true)
  candidate.merge!('format' => 'knockout', 'knockout' => metadata, 'rematch' => true)
  candidate['schedule_id'], candidate['matches'] = T::KnockoutSchedule.matches(metadata: metadata, generation: candidate['roster_generation'])
  service = f.services.fetch('Alice')
  previews = candidate['matches'].map do |match|
    service.forfeit_preview(match_id: match['match_id'], leg: match['leg'], expected_schedule_id: candidate['schedule_id'], all_zero: true)
  end
  keys = candidate['matches'].map { |match| service.send(:anchor, candidate, 5, match, 'forfeit')['operation_key'] }
  original = f.documents.method(:insert_as)
  arrived, release, failures = Queue.new, Queue.new, Queue.new
  f.documents.define_singleton_method(:insert_as) do |values, user|
    if user == 'Alice' && keys.include?(values['operation_key']) && values['part_index'] == 0
      # Both genuine calls pass their checks before either HTTP request reaches
      # the server. The accepted headers then lose their acknowledgements.
      arrived << values['operation_key']
      release.pop
      original.call(values, user)
      raise IOError, 'Lost paired header ACK'
    end
    original.call(values, user)
  end
  threads = previews.map do |preview|
    Thread.new do
      begin
        service.confirm_forfeit(preview: preview)
        failures << nil
      rescue StandardError => error
        failures << error
      end
    end
  end
  Timeout.timeout(10) { 2.times { arrived.pop } }
  2.times { release << true }
  threads.each { |thread| assert(thread.join(10), 'Archive worker did not finish') }
  f.documents.define_singleton_method(:insert_as, original)
  2.times { assert(failures.pop.is_a?(IOError), 'The fixture did not lose the actual header ACK') }
  pending = service.operations.select { |row| row['status'] == 'attempted' }
  assert_equal(2, pending.size)
  assert_equal([], service.result_view['results'], 'Partial headers became results')
  service.reconcile(pending.first['id'])
  view = service.result_view
  assert_equal(1, view['results'].size, 'Neither exact organizer intent could recover')
  assert_equal('all_zero', view['results'].first.dig('summary', 'resolution'))
  assert_equal(true, view['completed'])
  writes = f.documents.insert_count
  error = assert_raises(T::OrdinaryMatchService::Blocked) { service.reconcile(pending.last['id']) }
  assert_equal(:result_already_recorded, error.code, 'The other leg remained uncertain instead of observing the accepted no-award decision')
  assert_equal(writes, f.documents.insert_count, 'The voided return published a second result')
  assert_equal(view, f.services.fetch('Bob').result_view)
ensure
  threads&.each { |thread| thread.kill if thread.alive? }
end

puts 'PASS simultaneous paired partial administrative writes recover one exact owner intent without permitting entry or manufacturing a return-leg result'
