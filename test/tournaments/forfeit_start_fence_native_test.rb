require_relative '../support/tournament_forfeit_native'
require_relative '../../lib/tournaments/server_phase_plan'
T = GameRoomTournaments

def other_worker
  output = Queue.new
  worker = Thread.new do
    begin
      output << yield
    rescue StandardError => error
      output << error
    end
  end
  assert(worker.join(10), 'Independent entry worker did not finish')
  output.pop
ensure
  if worker
    primary_error = $!
    begin
      worker.kill if worker.alive?
      raise 'Independent entry worker cleanup timed out' unless worker.join(5)
    rescue StandardError => error
      raise unless primary_error
      warn "Entry worker cleanup failed: #{error.class}: #{error.message}"
    end
  end
end

def on_forfeit_header(fixture, preview, &action)
  key = fixture.services.fetch('Alice').send(:anchor, fixture.candidate, 5,
    preview.slice('match_id', 'leg'), 'forfeit')
  fixture.documents.on_insert = lambda do |row|
    next unless row['operation_key'] == key['operation_key'] && row['part_index'] == 0
    fixture.documents.on_insert = nil
    action.call
  end
end

[false, true].each do |waiting_table|
  TournamentForfeitNative.with_fixture do |f|
    table = nil
    if waiting_table
      table = f.h.as('Bob') { f.services.fetch('Bob').open_match(match_id: f.match['match_id'], leg: 1) }
      f.h.as('Alice') { f.services.fetch('Alice').open_match(match_id: f.match['match_id'], leg: 1) }
    end
    preview = f.preview
    assert_equal(waiting_table ? 'unstarted' : 'unbound', preview.dig('boundary', 'status'))
    intercepted = false
    native_before = f.h.broker.cores.size
    on_forfeit_header(f, preview) do
      intercepted = true
      assert_equal([], f.services.fetch('Bob').result_view['results'], 'Incomplete intent became a sporting result')
      error = other_worker do
        f.h.as('Bob') do
          if waiting_table
            f.services.fetch('Bob').start_parameters(table, players: f.h.users)
          else
            f.services.fetch('Bob').open_match(match_id: f.match['match_id'], leg: 1)
          end
        end
      end
      assert(error.is_a?(T::ServerPlanArchive::Unconfirmed), "Partial administrative intent did not fence entry: #{error.inspect}")
      unless waiting_table
        assert_raises(T::ServerPlanArchive::Unconfirmed) { f.services.fetch('Bob').send(:claim_creator, f.candidate, 5, f.match) }
      end
      assert_equal(native_before, f.h.broker.cores.size, 'Blocked entry created a new native table')
      assert_equal(nil, f.h.session, 'Blocked entry started a native game')
    end
    view = f.confirm(preview)
    assert(intercepted, 'Test did not pause the actual archive at its accepted header')
    assert_equal('ordinary-match-forfeit-v3', view['results'].first['kind'])
    assert_equal(view, f.services.fetch('Bob').result_view)
  end
end

TournamentForfeitNative.with_fixture do |f|
  candidate = f.candidate
  metadata = T::KnockoutSchedule.direct_metadata(seeds: candidate['roster'], generation: candidate['roster_generation'],
    publication_digest: candidate['publication_digest'], rematch: true)
  candidate.merge!('format' => 'knockout', 'knockout' => metadata, 'rematch' => true)
  candidate['schedule_id'], candidate['matches'] = T::KnockoutSchedule.matches(metadata: metadata, generation: candidate['roster_generation'])
  first, second = candidate.fetch('matches')
  service = f.services.fetch('Alice')
  preview = service.forfeit_preview(match_id: first['match_id'], leg: first['leg'],
    expected_schedule_id: candidate['schedule_id'], all_zero: true)
  intercepted = false
  on_forfeit_header(f, preview) do
    intercepted = true
    error = other_worker { f.h.as('Bob') { f.services.fetch('Bob').open_match(match_id: second['match_id'], leg: second['leg']) } }
    assert(error.is_a?(T::ServerPlanArchive::Unconfirmed), 'An incomplete no-award receipt allowed the return leg to open')
  end
  view = f.confirm(preview)
  assert(intercepted)
  assert_equal(true, view['completed'])
  assert_equal([second.slice('match_id', 'leg').merge('source' => first.slice('match_id', 'leg'))], view['settled_without_play'])
  assert_equal(nil, f.h.session)
end

TournamentForfeitNative.with_fixture do |f|
  preview = f.preview
  on_forfeit_header(f, preview) { raise IOError, 'Lost partial administrative ACK' }
  assert_raises(IOError) { f.confirm(preview) }
  assert_equal([], f.services.fetch('Bob').result_view['results'])
  pending = f.services.fetch('Alice').operations.find { |row| row['status'] == 'attempted' }
  assert(pending, 'Fixture did not retain the uncertain immutable intent')
  before = f.documents.insert_count
  f.services.fetch('Alice').reconcile(pending['id'])
  assert(f.documents.insert_count > before, 'Recovery did not finish the missing payload')
  writes = f.documents.insert_count
  f.services.fetch('Alice').reconcile(pending['id'])
  assert_equal(writes, f.documents.insert_count, 'Confirmed recovery duplicated the administrative result')
  assert_equal(['alice'], f.services.fetch('Bob').result_view['results'].first.dig('summary', 'winners'))
end

TournamentForfeitNative.with_fixture do |f|
  service = f.services.fetch('Bob')
  table = f.h.as('Bob') { service.open_match(match_id: f.match['match_id'], leg: 1) }
  f.h.as('Alice') { f.services.fetch('Alice').open_match(match_id: f.match['match_id'], leg: 1) }
  preview = f.preview
  binding = service.send(:read_match_binding, f.candidate, 5, f.match, nil)
  start_key = service.send(:entry_anchor, f.candidate, 5, f.match, 'start', binding)
  start = {'kind' => 'ordinary-match-start-v1', 'publication_ref' => f.candidate['publication_ref'],
    'schedule_id' => f.candidate['schedule_id'], 'match_id' => f.match['match_id'], 'leg' => 1,
    'binding_digest' => service.send(:binding_digest, binding), 'session_id' => binding['session_id']}
  pending = service.instance_variable_get(:@journal).prepare(kind: 'plan_document', intent_id: 'pending-start',
    values: start_key.merge('kind' => 'plan_document', 'document_json' => JSON.generate(start)))
  on_forfeit_header(f, preview) { raise IOError, 'Lost partial administrative ACK' }
  assert_raises(IOError) { f.confirm(preview) }
  writes = f.documents.insert_count
  assert_raises(T::ServerPlanArchive::Unconfirmed) { service.reconcile(pending['id']) }
  assert_raises(T::ServerPlanArchive::Unconfirmed) { service.send(:retain_start_intent, f.candidate, 5, f.match, binding) }
  assert_equal(writes, f.documents.insert_count, 'Recovery or creator election wrote past an administrative fence')
  assert_equal(nil, f.h.session)
  f.confirm(preview)
  # Checking previously confirmed entry metadata must remain idempotent even
  # after the fixture is settled. It cannot launch another native game.
  writes = f.documents.insert_count
  service.operations.select { |row| row['status'] == 'confirmed' }.each { |row| service.reconcile(row['id']) }
  assert_equal(writes, f.documents.insert_count)
end

TournamentForfeitNative.with_fixture do |f|
  service = f.services.fetch('Alice')
  preview = f.preview
  key = service.send(:anchor, f.candidate, 5, f.match, 'forfeit')
  # An untrusted participant cannot prevent the organizer's match by writing
  # parts under the same discovery key.
  f.documents.insert_as(T::ServerPlanDocument.encode(preview, anchor: key).first, 'Bob')
  f.start
  assert(!f.h.replay('Alice').finished?)
end

puts 'PASS incomplete administrative intents fence other-account creation, existing-table start and paired returns; read-only results, exact recovery and authenticated ownership preserved'
