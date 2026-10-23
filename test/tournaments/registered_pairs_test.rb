require_relative '../support/binary_rules_load' if ARGV.first
require_relative '../support/tournament_fixed_teams'
include TournamentFixedTeamsSupport
c, service, reference = fixture
id = service.list['announcements'].first['__id']
choose = ->(actor, partner, intent) do
  c.actor=actor
  c.service(journal:c.reopen_journal).set_partner(tournament_id:id,account:actor,partner:partner,intent_id:intent)
end
[%w[ala anna], %w[bartek beata], %w[celina cezary]].each do |a,b|
  assert_equal('confirmed', choose.call(a,b,"pair:#{a}")['status'])
  assert_equal('confirmed', choose.call(b,a,"accept:#{b}")['status'])
end
c.actor='Organizator'
assert_equal(3, service.list['pairs'].size)
assert_equal(service.list['pairs'], c.service(journal: c.reopen_journal).list['pairs'])
with_backend(c) do |backend|
  shown = backend.preview_pairs(publication_ref: reference, pairs: service.list['pairs'].map { |row| row['accounts'] }, team_template: TEMPLATE, intent_id: 'registered-pairs')
  record = backend.accept(preview: shown)
  assert_equal(6, record['evidence']['plan']['matches'].size)
  choose.call('ala',nil,'dissolve-a')
  choose.call('bartek',nil,'dissolve-b')
  choose.call('ala','bartek','request-new')
  choose.call('bartek','ala','accept-new')
  c.actor='Organizator'
  error = assert_raises(T::Publication::Invalid) { backend.current(intent_id: 'registered-pairs') }
  assert_equal(:source_changed, error.code)
end
assert_equal([%w[ala bartek], %w[celina cezary]], service.list['pairs'].map { |row| row['accounts'] })
c.actor = 'Anna'
participant = c.service(journal: c.reopen_journal)
error = assert_raises(T::PublicService::Error) { participant.set_partner(tournament_id: id, account: 'anna', partner: 'ala', intent_id: 'busy') }
assert_equal(:partner_unavailable, error.code)
c.actor = 'Organizator'
service.remove_participant(tournament_id: id, account: 'ala')
assert_equal([%w[celina cezary]], service.list['pairs'].map { |row| row['accounts'] })
puts 'PASS persisted consensual pairs, occupied partner, organizer removal and stale execution guard'
