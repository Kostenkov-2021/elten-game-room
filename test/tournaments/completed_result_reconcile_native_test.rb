require_relative '../support/tournament_forfeit_native'
T = GameRoomTournaments

def finish_native(fixture)
  fixture.start
  9.times do
    replay = fixture.h.replay('Alice')
    break if replay.finished?
    player = replay.current_player
    fixture.h.submit(player, fixture.h.game.legal_actions(replay, player).first)
  end
  assert(fixture.h.replay('Alice').finished?)
end

def expired_source(service)
  service.instance_variable_set(:@completed_source, service.instance_variable_get(:@source))
  service.instance_variable_set(:@source, -> { raise T::Publication::Invalid, :missing_publication })
end

TournamentForfeitNative.with_fixture do |fixture|
  finish_native(fixture)
  service = fixture.services.fetch('Alice')
  service.collect(service.instance_variable_get(:@bindings).fetch(fixture.h.table.fetch('__id')))
  record = service.operations.find { |row| JSON.parse(row['values']['document_json'])['kind'] == 'ordinary-match-result-v1' }
  assert_equal('confirmed', record.fetch('status'))
  document = JSON.parse(record.fetch('values').fetch('document_json'))
  assert(!document.key?('schedule_id'), 'The test must exercise the actual native receipt, not a new invented format')
  expired_source(service)
  writes = fixture.documents.insert_count
  assert_equal(record, service.reconcile(record.fetch('id')), 'A complete expired ordinary result lost its read-only reconciliation')
  assert_equal(writes, fixture.documents.insert_count)
  fixture.candidate['publication_ref'] = fixture.candidate.fetch('publication_ref').merge('publication_key' => 'different')
  error = assert_raises(T::OrdinaryMatchService::Blocked) { service.reconcile(record.fetch('id')) }
  assert_equal(:source_changed, error.code, 'Expired recovery accepted a different source')
  assert_equal(writes, fixture.documents.insert_count)
end

TournamentForfeitNative.with_fixture do |fixture|
  finish_native(fixture)
  service = fixture.services.fetch('Alice')
  fixture.documents.on_insert = ->(row) do
    raise IOError, 'Ordinary-result header accepted; acknowledgement lost' if row['part_index'] == 0
  end
  assert_raises(IOError) do
    service.collect(service.instance_variable_get(:@bindings).fetch(fixture.h.table.fetch('__id')))
  end
  record = service.operations.find { |row| JSON.parse(row['values']['document_json'])['kind'] == 'ordinary-match-result-v1' }
  assert_equal('attempted', record.fetch('status'))
  expired_source(service)
  fixture.documents.on_insert = nil
  writes = fixture.documents.insert_count
  assert_raises(T::ServerPlanArchive::Unconfirmed) { service.reconcile(record.fetch('id')) }
  assert_equal(writes, fixture.documents.insert_count, 'Read-only expiry recovery appended a missing natural-result part')
  assert_equal('attempted', service.operations.find { |row| row['id'] == record['id'] }.fetch('status'))
end
puts 'PASS completed native-result reconciliation: original receipt format, exact source, complete evidence and zero expired appends'
