require_relative '../support/tournament_forfeit_native'
require_relative '../../lib/sports_rankings/result'

TournamentForfeitNative.with_fixture(game:GameRoomGames::AxelPong.new,
  options:{'target'=>'custom','custom_target'=>2}) do |fixture|
  service=fixture.services.fetch('Alice')
  rows=[]
  service.instance_variable_set(:@rankings_observer,lambda do |candidate,match,receipt,people,time|
    rows << GameRoomSportsRankings::Result.from_tournament(game:fixture.h.game,candidate:candidate,
      match:match,receipt:receipt,players:people,finished_at:time)
  end)
  # Fixture documents use explicit native server times, just like live rows.
  table=fixture.documents
  original=table.method(:insert_as)
  table.define_singleton_method(:insert_as) do |values,user|
    original.call(values,user).tap { |row| row['__insertion_time']=1_792_800_000 }
  end
  fixture.confirm(fixture.preview)
  assert_equal(1,rows.size,'Confirmed technical result did not reach the ranking observer')
  result=GameRoomSportsRankings::Result.parse(rows.first)
  assert_equal([2,0],result['sides'].map { |side| side['goals'] })
  first=rows.first
  service.reconcile(service.operations.first['id'])
  assert_equal(first,rows.last,'Cold receipt recovery changed the ranked match identity')
  service.instance_variable_set(:@rankings_observer,->(*) {raise IOError,'Ranking server unavailable'})
  service.reconcile(service.operations.first['id'])
  assert_equal(true,service.result_view['completed'],'Ranking outage invalidated a confirmed sporting result')
end
puts 'PASS sports tournament handoff: actual administrative receipt, technical goals, canonical time, recovery identity and isolated ranking failure'
