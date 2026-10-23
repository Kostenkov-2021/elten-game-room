require_relative '../support/temporary_directory'
require_relative '../support/native_room_harness'
require_relative '../support/readiness_plan_table'
require_relative '../../lib/tournaments/server_proposal_service'
include GameRoomTest::Assertions
T = GameRoomTournaments

GameRoomTest::TemporaryDirectory.create('proposal-daily-window-') do |directory|
  now = Time.utc(2026,10,14,11,59,30).to_i
  table = ReadinessPlanTableSupport::Table.new(user:-> {'Alice'}, clock:-> {now})
  journal = T::OperationJournal.new(directory:directory, owner:'alice', backend_identity:'proposal-daily-window')
  candidate = {'publication_ref'=>{'author'=>'alice','publication_key'=>'fixture'}, 'schedule_id'=>'a'*64,
    'publication_digest'=>'b'*64, 'roster_generation'=>'c'*64, 'state'=>'observed_candidate','finality'=>'unknown',
    'start_allowed'=>false, 'dispatch_allowed'=>false, 'finalize_allowed'=>false, 'roster'=>%w[alice bob],
    'timezone'=>'UTC','windows'=>[], 'starts_at'=>Time.utc(2026,10,14,10).to_i,
    'daily_hours'=>{'start'=>'11:00','end'=>'12:00','utc_offset_minutes'=>0},
    'matches'=>[{'match_id'=>'d'*64,'leg'=>1,'players'=>%w[alice bob]}]}
  service = T::ServerProposalService.new(table:table, journal:journal, user:-> {'Alice'},
    source:-> {{'candidate'=>candidate,'tournament_id'=>7}}, readiness:nil, clock:-> {now})
  match = {match_id:'d'*64,leg:1}
  initial = service.propose(**match,intent_id:'before-daily-close')
  assert_equal(30, initial.dig('window','closes')-now, 'Invitation outlives the selected daily playing hours')
  now = Time.utc(2026,10,14,12).to_i
  assert_equal('expired', service.snapshot(**match)['state'])
  before = table.insert_count
  error = assert_raises(T::Publication::Invalid) { service.propose(**match,intent_id:'outside-daily-hours') }
  assert_equal(:outside_window,error.code)
  assert_equal(before,table.insert_count,'Outside-hours invitation appended data before refusal')
  now = Time.utc(2026,10,15,11).to_i
  following = service.propose(**match,intent_id:'next-daily-opening')
  assert_equal('awaiting_consent',following['state'])
  assert_equal(300,following.dig('window','closes')-now)
end
puts 'PASS proposal daily window survives scoped-source projection: clipped consent, outside-hours refusal before append and next-day opening'
