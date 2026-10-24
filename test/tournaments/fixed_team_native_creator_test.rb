require_relative '../support/tournament_fixed_team_native_service'
include GameRoomTest::Assertions

broker=TournamentFixedTeamNativeService::Broker.new({})
alice=broker.endpoint('Alice').create(metadata:{'owner'=>'Alice'},participant_metadata:{},
  capacity:2,visibility: :public,discovery_metadata:{},stack_entries:4096,stack_entry_bytes:4096)
broker.endpoint('Bob').discover_sessions(sources:[:public]).items.first.join
alice.transfer_ownership(alice.participants.find { |person|person.user=='Bob' })
archive=broker.dump
assert(!archive.fetch('cores').first.key?('creator'), 'The SDK fixture field entered the exact archive schema')
restored=TournamentFixedTeamNativeService::Broker.new(archive)
assert_equal('Bob',restored.cores.fetch(alice.id).owner)
assert_equal([alice.id],restored.endpoint('Alice').discover_sessions(sources:[:created]).items.map(&:id),
  'Cold restore confused the original creator with the current native owner')
assert_equal([],restored.endpoint('Bob').discover_sessions(sources:[:created]).items)
puts 'PASS local native-service archive: exact schema, current host and original creator remain distinct'
