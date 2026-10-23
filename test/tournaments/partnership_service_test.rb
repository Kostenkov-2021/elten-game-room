require_relative '../support/tournament_public_service'
require_relative '../../lib/tournaments/public_service'
include TournamentPublicServiceSupport
include GameRoomTest::Assertions
T = GameRoomTournaments
sandbox do |context|
  context.actor = 'Organizer'
  service = -> { context.service(journal: context.reopen_journal) }
  values = params('spades', timezone: 'UTC')
  values[:draft] = values[:draft].merge('players_per_match'=>4,
    'game_options'=>GameRoomGames::CATALOG.build('spades').normalize_options('team_size'=>2))
  id = service.call.publish(**values).fetch('evidence').fetch('canonical_id')
  %w[Alpha Beta Gamma Delta Epsilon Zeta].each do |name|
    context.actor = name
    service.call.join(tournament_id: id)
  end
  choose = ->(actor, other, intent) do
    context.actor = actor
    service.call.set_partner(tournament_id: id, account: actor, partner: other, intent_id: intent)
  end
  choose.call('Alpha', 'Beta', 'first')
  old = service.call.list.fetch('pair_requests').first.fetch('key')
  context.actor = 'Alpha'
  service.call.partnership_action(tournament_id: id, action: 'request', partner: 'Gamma', request_key: old, intent_id: 'replace')
  assert_equal(['gamma'], service.call.list['pair_requests'].map { |row| row['to'] })
  context.actor = 'Beta'
  writes = context.inserts.length
  error = assert_raises(T::PublicService::Error) do
    service.call.partnership_action(tournament_id: id, action: 'accept', partner: 'Alpha', request_key: old, intent_id: 'old-accept')
  end
  assert_equal(:source_changed, error.code)
  assert_equal(writes, context.inserts.length)
  choose.call('Gamma', 'Alpha', 'accept-current')
  assert_equal([%w[alpha gamma]], service.call.list['pairs'].map { |row| row['accounts'] })
  assert_equal(true, choose.call('Gamma', 'Alpha', 'accept-current').dig('evidence', 'pairing_applied'))
  context.actor = 'Organizer'
  error = assert_raises(T::PublicService::Error) { service.call.set_partner(tournament_id: id, account: 'Beta', partner: 'Delta', intent_id: 'override') }
  assert_equal(:own_partnership_only, error.code)
  assert_equal('confirmed', service.call.complete_partnerships(tournament_id: id, starting: true)['status'])
  pairs = service.call.list['pairs'].map { |row| row['accounts'] }
  assert_equal(3, pairs.size)
  assert(pairs.include?(%w[alpha gamma]))
  assert_equal(%w[alpha beta delta epsilon gamma zeta], pairs.flatten.sort)
  writes = context.inserts.length
  service.call.complete_partnerships(tournament_id: id, starting: true)
  assert_equal(writes, context.inserts.length, 'Opening/retrying a completed draw rerolled the teams')
  assert_equal(pairs, service.call.list['pairs'].map { |row| row['accounts'] })
  changes = service.call.list.fetch('partner_changes')
  assert_equal(2, changes.count { |row| row['kind'] == 'assigned' })
  context.actor = 'Zeta'
  service.call.withdraw(tournament_id: id)
  context.actor = 'Organizer'
  writes = context.inserts.length
  error = assert_raises(T::PublicService::Error) { service.call.complete_partnerships(tournament_id: id, starting: true) }
  assert_equal(:incomplete_pairs, error.code)
  assert_equal(1, error.details.fetch(:count))
  assert_equal(writes, context.inserts.length)
end
sandbox do |context|
  context.actor='Organizer'
  service=-> {context.service(journal:context.reopen_journal)}
  values=params('spades',timezone:'UTC',intent_id:'scheduled-pairs')
  values[:draft]=values[:draft].merge('players_per_match'=>4,'starts_at'=>300,'deadline_at'=>1000,'windows'=>[],
    'game_options'=>GameRoomGames::CATALOG.build('spades').normalize_options('team_size'=>2))
  id=service.call.publish(**values).dig('evidence','canonical_id')
  error=assert_raises(T::PublicService::Error){service.call.complete_partnerships(tournament_id:id,starting:true)}
  assert_equal({count:0,minimum:4},error.details)
  %w[Alpha Beta].each{|actor|context.actor=actor;service.call.join(tournament_id:id)}
  context.actor='Organizer'
  error=assert_raises(T::PublicService::Error){service.call.complete_partnerships(tournament_id:id,starting:true)}
  assert_equal({count:2,minimum:4},error.details)
  %w[Gamma Delta].each{|actor|context.actor=actor;service.call.join(tournament_id:id)}
  context.actor='Alpha'
  assert_raises(T::PublicService::Error){service.call.complete_partnerships(tournament_id:id)}
  context.now=301
  assert_equal('confirmed',service.call.complete_partnerships(tournament_id:id)['status'])
  pairs=service.call.list['pairs']
  assert_equal(2,pairs.length)
  assert_equal(%w[alpha beta delta gamma],pairs.flat_map{|pair|pair['accounts']}.sort)
  writes=context.inserts.size
  context.actor='Beta'
  service.call.complete_partnerships(tournament_id:id)
  assert_equal(writes,context.inserts.size,'A second scheduled-start coordinator rerolled the teams')
  assert_equal(pairs,service.call.list['pairs'])
end
puts 'PASS partnership service/gateway/journal: exact consent, races, manual/scheduled completion, zero/two/four free entrants, blocked counts and no reroll'
