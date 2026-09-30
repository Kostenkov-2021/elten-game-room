def _(text); text; end
require_relative "../../../games/spades"
def assert(condition,message); raise message unless condition; end

game=GameRoomGames::Spades.new
players=%w[A B C D]
state={players:players,options:game.normalize_options('team_size'=>2),round:1,dealer_index:3,
  scores:{'team:0'=>0,'team:1'=>0},bids:{'A'=>4,'B'=>3,'C'=>3,'D'=>0},
  tricks:{'A'=>4,'B'=>0,'C'=>0,'D'=>0},phase: :playing,current_player:'B',
  spades_broken:false,winner:nil,current_trick:[{player:'A',card:'2C'}],
  hands:{'A'=>%w[6C 7C 8C 9C TC QC AC AS], 'B'=>%w[3C KC TD JD QD KD AD TH JH],
    'C'=>%w[4C QH KH AH 2S 3S 4S 5S 6S], 'D'=>%w[5C JC 7S 8S 9S TS JS QS KS]}}
events=[{'id'=>1,'action'=>'deal','actor'=>'A','value'=>'1|3|00000000000000000000000000000000'}]
[%w[5D 2D 3D 4D],%w[5H 2H 3H 4H],%w[9D 6D 7D 8D],%w[9H 6H 7H 8H]].each do |cards|
  players.zip(cards).each { |player,card| events << {'id'=>events.length+1,'action'=>'play','actor'=>player,'value'=>card} }
end
events << {'id'=>18,'action'=>'play','actor'=>'A','value'=>'2C'}
make_replay=lambda do |s|
  GameRoomGames::Replay.new(state:s,players:players,current_player:s[:current_player],history:[],accepted_events:events)
end
r=make_replay.call(state)
context=game.bot_decision_context(r,'B')
planner=game.send(:spades_round_planner)
assert(planner.last_failure.nil?,'valid state must not silently fall back from planning')
risks=context[:round_plan][:partner_nil_risks]
assert(risks['KC']==0 && risks['3C']>=0.25,'recognize avoidable current-trick danger to partner nil')
choice=game.bot_strategy.choose(actions:game.legal_actions(r,'B'),actor:'B',game:game,replay:r,random_source:GameRoomRandom::SeededSource.new(212))
assert(choice['card']=='KC','protect partner against a significant public-information risk')
other=Marshal.load(Marshal.dump(state));other[:hands]['C'],other[:hands]['D']=other[:hands]['D'],other[:hands]['C']
other_context=game.bot_decision_context(make_replay.call(other),'B')
assert(other_context[:round_plan][:partner_nil_risks]==risks,'nil risk cannot read the real hidden partner hand')

safe=Marshal.load(Marshal.dump(state))
safe[:current_trick]=[{player:'D',card:'2C'},{player:'A',card:'AC'}]
world=SpadesPlanning::RoundPlanner::PlanningWorld.new(state:safe,weight:1.0)
assert(planner.send(:immediate_partner_nil_risks,safe,'B',%w[3C KC],[world]).empty?,
  'do not burn control to protect a partner who already discarded safely')
small_difference={round_plan:{partner_nil_risks:{'3C'=>0.10,'KC'=>0.0}}}
assert(game.send(:bot_partner_nil_risk_adjustment,{'card'=>'3C'},small_difference)==0,
  'uncertain small differences do not override future control')
puts 'Audit 212: fair nil protection, hidden information and conservation guards passed'
