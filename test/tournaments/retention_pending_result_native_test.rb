require_relative '../support/tournament_local_workspace'
require_relative '../support/tournament_server_plan_table'
require_relative '../support/host_source'
require EltenTestHost.file('src/eltenlink/error.rb')
require_relative '../../lib/tournaments/server_workspace'
include TournamentLocalWorkspaceSupport
include GameRoomTest::Assertions
T = GameRoomTournaments
DAY = 86_400

def retention_fixture(context, groups: false)
  publications = T::LocalTestTables.new(directory: File.join(context.directory, 'server'),
    user: -> { context.user }, clock: -> { context.now })
  documents = TournamentServerPlanTableSupport::Table.new(user: -> { context.user })
  documents.on_insert = ->(row) { row['__insertion_time'] = context.now }
  provider = Object.new
  provider.define_singleton_method(:available?) { true }
  provider.define_singleton_method(:fetch) { |name| name == 'tournament_plan_documents' ? documents : publications.fetch(name) }
  make = -> do
    T::ServerWorkspace.new(program: context.program, registry: GameRoomGames::CATALOG,
      user: -> { context.user }, alert: ->(text) { context.alerts << text }, clock: -> { context.now },
      readiness_clock: -> { context.now }, provider_factory: -> { provider })
  end
  values = params('tic_tac_toe', timezone: 'UTC', registration_closes_at: 0)
  values[:draft] = values[:draft].merge('windows' => [], 'starts_at' => 0, 'deadline_at' => 0)
  if groups
    values[:draft] = values[:draft].merge('format' => 'groups_knockout', 'group_advancement' => T::GroupAdvancement::COMPACT,
      'group_count' => nil, 'places_per_group' => nil)
  end
  publication = make.call.publish(**values)
  assert_equal('confirmed', publication&.fetch('status'), context.alerts.inspect)
  id = publication.fetch('evidence').fetch('canonical_id')
  (groups ? %w[Second Third Fourth] : %w[Second Third]).each do |user|
    context.user = user
    assert_equal('confirmed', make.call.join(id)&.fetch('status'))
  end
  context.user = 'RealOwner'
  workspace = make.call
  row = workspace.load.fetch('announcements').first
  reference = {'author' => row.fetch('__insertion_user'), 'publication_key' => row.fetch('publication_key')}
  assert_equal('confirmed', workspace.change_phase(tournament_id: id, action: 'start', intent_id: 'start',
    expected_generation: T::RegistrationProjection.publication_generation(row))&.fetch('status'))
  context.now += 29 * DAY
  candidate = workspace.schedule_overview(publication_ref: reference).fetch('candidate')
  [make, documents, id, reference, candidate]
end

sandbox do |context|
  make, documents, id, reference, candidate = retention_fixture(context)
  service = make.call.ordinary_service(publication_ref: reference, lobby: nil, games: nil, transport: nil)
  match = candidate.fetch('matches').first
  preview = service.forfeit_preview(match_id: match.fetch('match_id'), leg: match.fetch('leg'),
    loser: match.fetch('players').last, expected_schedule_id: candidate.fetch('schedule_id'))
  documents.on_insert = ->(row) do
    row['__insertion_time'] = context.now
    raise IOError, 'Header accepted; acknowledgement lost' if row['part_index'] == 0
  end
  assert_raises(IOError) { service.confirm_forfeit(preview: preview) }
  attempted = service.operations.find { |record| record['status'] == 'attempted' }
  assert(attempted)
  assert_equal(1, documents.rows.size)
  assert_equal('RealOwner', documents.rows.first['__insertion_user'])
  assert_equal([], service.result_view.fetch('results'), 'An incomplete receipt became a result')
  context.now += 2 * DAY
  writes = documents.insert_count
  %w[RealOwner Second].each do |user|
    context.user = user
    workspace = make.call
    [workspace.load, workspace.directory_on_worker].each do |view|
      retained = view.fetch('announcements').find { |row| row['__id'] == id }
      assert(retained, 'An uncertain result was treated as abandonment')
      assert_equal('unconfirmed', retained['plan_error'])
      assert(!retained['expires_at'], 'An uncertain upload fabricated a new retention deadline')
      assert(!retained['sporting_completed'])
    end
  end
  assert_equal(writes, documents.insert_count, 'Directory reads appended recovery records')
  context.user = 'RealOwner'
  documents.on_insert = ->(row) { row['__insertion_time'] = context.now }
  service.close
  service = make.call.ordinary_service(publication_ref: reference, lobby: nil, games: nil, transport: nil)
  assert_equal('confirmed', service.reconcile(attempted.fetch('id')).fetch('status'), 'Full exact recovery lost its final acknowledgement to expiry')
  after = documents.insert_count
  assert_equal([], make.call.load.fetch('announcements'), 'Completing an old upload revived an expired tournament')
  assert_equal('confirmed', service.reconcile(attempted.fetch('id')).fetch('status'), 'Cold evidence could not confirm an expired receipt')
  assert_equal(after, documents.insert_count, 'Confirmed-result reconciliation appended another copy')
  error = assert_raises(T::Publication::Invalid) { service.open_match(match_id: match['match_id'], leg: match['leg']) }
  assert_equal(:missing_publication, error.code, 'Read-only acknowledgement recovery granted fresh entry')
  assert_equal([], context.alerts)
ensure
  service&.close
end

sandbox do |context|
  make, documents, _id, reference, candidate = retention_fixture(context)
  service = make.call.ordinary_service(publication_ref: reference, lobby: nil, games: nil, transport: nil)
  match = candidate.fetch('matches').first
  preview = service.forfeit_preview(match_id: match['match_id'], leg: match['leg'],
    loser: match['players'].last, expected_schedule_id: candidate['schedule_id'])
  original_insert = documents.method(:insert)
  documents.define_singleton_method(:insert) { |_values| raise IOError, 'No part accepted' }
  assert_raises(IOError) { service.confirm_forfeit(preview: preview) }
  attempted = service.operations.find { |record| record['status'] == 'attempted' }
  assert(attempted)
  documents.define_singleton_method(:insert, original_insert)
  context.now += 2 * DAY
  assert_equal([], make.call.load.fetch('announcements'))
  assert_raises(T::ServerPlanArchive::Unconfirmed) { service.reconcile(attempted.fetch('id')) }
  assert_equal([], documents.rows, 'Evidence-only reconciliation completed an expired upload')
  assert_equal('attempted', service.operations.find { |row| row['id'] == attempted['id'] }.fetch('status'))
ensure
  service&.close
end

sandbox do |context|
  make, documents, id, reference, candidate = retention_fixture(context, groups: true)
  workspace = make.call
  service = workspace.ordinary_service(publication_ref: reference, lobby: nil, games: nil, transport: nil)
  candidate.fetch('matches').each do |match|
    service.confirm_forfeit(preview: service.forfeit_preview(match_id: match['match_id'], leg: match['leg'],
      loser: match['players'].sort.last, expected_schedule_id: candidate['schedule_id']))
  end
  service.close
  documents.on_insert = ->(row) do
    row['__insertion_time'] = context.now
    raise IOError, 'Sporting phase header accepted; acknowledgement lost' if row['part_index'] == 0
  end
  assert_equal(nil, workspace.advance_phase(publication_ref: reference, expected_schedule_id: candidate['schedule_id']))
  assert(workspace.last_error.is_a?(IOError))
  pending = workspace.operations.find { |row| JSON.parse(row.fetch('values').fetch('document_json', '{}'))['kind'] == 'server-sporting-phase-v1' }
  assert_equal('attempted', pending.fetch('status'))
  context.now += 31 * DAY
  %w[RealOwner Second].each do |user|
    context.user = user
    retained = make.call.load.fetch('announcements').find { |row| row['__id'] == id }
    assert_equal('incomplete_plan_document', retained&.fetch('plan_error'))
  end
  context.user = 'RealOwner'
  documents.on_insert = ->(row) { row['__insertion_time'] = context.now }
  cold = make.call
  assert_equal('confirmed', cold.reconcile(pending.fetch('id'))&.fetch('status'), context.alerts.inspect)
  writes = documents.insert_count
  assert_equal([], make.call.load.fetch('announcements'), 'A late phase completion revived an expired tournament')
  assert_equal('confirmed', make.call.reconcile(pending.fetch('id'))&.fetch('status'))
  assert_equal(writes, documents.insert_count, 'Completed-phase reconciliation appended another document')
ensure
  service&.close
end
puts 'PASS native-worker retention: incomplete authenticated result stays uncertain, exact completed recovery is read-only, no resurrection or expired append'
