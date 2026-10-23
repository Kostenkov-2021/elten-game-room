require_relative '../support/new_games_fixture'
require_relative '../../games/rummy'
require_relative '../../lib/tournaments/game_result'
require_relative '../../lib/tournaments/standings'
require 'digest'

# Fixed legal local shuffle inputs, not hand/result injection or SDK receipts.
class RummyPlacementRandom
  Result = Struct.new(:values, keyword_init:true)
  attr_reader :calls
  def initialize(seed)
    @bytes=[seed].pack('H*').bytes
    @calls=[]
  end
  def roll(count:, sides:)
    @calls << [count,sides]
    raise 'Unexpected randomness' unless count==16 && sides==256
    Result.new(values:@bytes.map{|byte|byte+1})
  end
end
game=GameRoomGames::Rummy.new
players=%w[Alice Bob Carol]
options=game.normalize_options('elimination'=>true,'score_limit'=>1,'discard_mode'=>'none','thinking_time'=>0)
session={'options'=>JSON.generate(options)}
repository=NewGames116Repository.new(players)
build=lambda do |seed|
  source=RummyPlacementRandom.new(seed)
  events=[];actions=0;replay=game.replay(session,events,repository)
  append=lambda do |action|
    actor=events.empty? ? players.first : replay.current_player
    context=GameRoomGames::ActionContext.new(random_source:source,now:1_800_000_000+actions)
    replay=append_action(game,session,repository,events,replay,actor,{'action'=>action},context)
    actions+=1
    assert(replay.accepted_events==events,'A normal Rummy action was rejected')
  end
  append.call('deal')
  while replay.state[:stock].any?
    append.call('draw');append.call('end')
  end
  until replay.finished?
    assert(actions<=140,'The complete legal end-turn route did not terminate')
    append.call('end')
  end
  assert(source.calls==[[16,256]],'Result export changed shuffle consumption')
  {game:game,replay:replay,players:players.map{|name|{'username'=>name,'account'=>name.downcase}},
    options:options,event_count:events.size,events:events}
end
arguments=build.call('00000000000000000000000000000006')
assert(arguments[:event_count]==278 && Digest::SHA256.hexdigest(JSON.generate(arguments[:events]))==
  'b587b5b3db982a000cfa038b5539cf3cc01061ab704d6cd7ecf50a8f83fb8b17','Original complete Rummy route changed')
assert(game.participant_scores(arguments[:replay])=={'Alice'=>310,'Bob'=>265,'Carol'=>265} &&
  arguments[:replay].state[:winners]==%w[Bob Carol],'The actual game did not declare the shared first place')
type=GameRoomTournaments::GameResult
%w[game-owned-scores-v1 game-owned-result-v2 game-owned-result-v3
  game-owned-result-v4 game-owned-result-v5 game-owned-result-v6].each do |policy|
  expected={'participants'=>%w[alice bob carol],'winners'=>[],'draw'=>true,'scores'=>nil,'event_count'=>278}
  expected['score_order']='higher' if %w[game-owned-result-v4 game-owned-result-v5].include?(policy)
  if policy=='game-owned-result-v6'
    expected.merge!('scores'=>{'alice'=>310,'bob'=>265,'carol'=>265},'score_order'=>'lower')
  end
  assert(type.from_replay(**arguments,result_policy:policy)==expected,"Historical Rummy #{policy} changed")
end
before=Marshal.dump(arguments[:replay].state)
summary=type.from_replay(**arguments,result_policy:type::CURRENT_RESULT_POLICY)
assert(!summary['draw'] && summary['winners']==%w[bob carol],'Shared Rummy victory still becomes an all-player draw')
assert(summary['scores']=={'alice'=>310,'bob'=>265,'carol'=>265} && summary['score_order']=='lower','Declared lower small points changed')
rows=GameRoomTournaments::Standings.calculate(units:%w[alice bob carol],
  results:[summary.slice('participants','winners','scores','score_order','places').merge('id'=>'rummy')],
  points:GameRoomTournaments::Standings::MATCH_POINTS)
assert(rows.to_h{|row|[row['unit'],row['points']]}=={'alice'=>0,'bob'=>3,'carol'=>3},'Shared first-place points changed')
assert(Marshal.dump(arguments[:replay].state)==before,'Export mutated the finished game')
unique=build.call('00000000000000000000000000000000')
assert(unique[:replay].state[:winners].one?,'The complete unique-winner control is not unique')
assert(type.from_replay(**unique,result_policy:type::CURRENT_RESULT_POLICY)==
  type.from_replay(**unique,result_policy:'game-owned-result-v6'),'Unique-winner result changed')
puts 'PASS complete accepted Rummy matches: shared/unique winners, lower small points, unchanged state/RNG and exact persisted v1-v6 summaries'
