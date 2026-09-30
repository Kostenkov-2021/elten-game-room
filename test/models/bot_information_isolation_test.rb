require_relative "../support/audit_212_rules_and_decisions"
require_relative "../../lib/game_simulation"
require_relative "../../games/tysiac"

def audit_scores(game, state, actor, events=[])
  r=audit_replay(state);r.accepted_events=events
  before=Marshal.dump(state)
  scores=game.legal_actions(r,actor).map { |action| [action,game.bot_action_score(r,actor,action)] }
  assert(Marshal.dump(state)==before,'analysis must not change the real game state')
  scores
end

cases= %w[classic flip no_mercy].map { |deck| [GameRoomGames::Uno,{'deck'=>deck}] } +
  %w[simple polish joker custom].map { |profile| [GameRoomGames::Makao,{'profile'=>profile,'jack_requests_rank'=>true}] }
cases.each do |klass,options|
  game=klass.new
  env=GameRoomSimulation::Environment.new_game(game:game,players:%w[A B C],options:options,seed:213)
  state=env.replay.state;actor=env.active_actor
  others=state[:players]-[actor]
  changed=Marshal.load(Marshal.dump(state));pool=others.flat_map { |p| changed[:hands][p] }.reverse
  others.each { |p| changed[:hands][p]=pool.shift(changed[:hands][p].length) }
  changed[:draw_pile].reverse!;changed[:seed]='f'*32
  assert(audit_scores(klass.new,state,actor)==audit_scores(klass.new,changed,actor),"#{game.id} #{options}: hidden cards change evaluations")
end

%w[holdem draw].each do |variant|
  game=GameRoomGames::Poker.new
  env=GameRoomSimulation::Environment.new_game(game:game,players:%w[A B C],options:{'variant'=>variant},seed:212)
  st=env.replay.state;actor=env.active_actor
  st[:phase]=:exchange if variant=='draw'
  events=[{'action'=>'deal'},{'action'=>'bet','actor'=>'B','value'=>'raise|50'},
    {'action'=>'exchange','actor'=>'B','value'=>'2H,3H'}]
  altered=Marshal.load(Marshal.dump(st));others=st[:players]-[actor]
  pool=others.flat_map { |p| altered[:hands][p] }.reverse
  others.each { |p| altered[:hands][p]=pool.shift(altered[:hands][p].length) }
  changed_events=Marshal.load(Marshal.dump(events));changed_events[-1]['value']='KH,QH'
  assert(audit_scores(GameRoomGames::Poker.new,st,actor,events)==audit_scores(GameRoomGames::Poker.new,altered,actor,changed_events),'Poker may see discard count, not discard identity')
end

game=GameRoomGames::NinetyNine.new
env=GameRoomSimulation::Environment.new_game(game:game,players:%w[A B C],seed:212)
state=env.replay.state;actor=env.active_actor
changed=Marshal.load(Marshal.dump(state));others=state[:players]-[actor]
pool=others.flat_map { |p| changed[:hands][p] }.reverse
others.each { |p| changed[:hands][p]=pool.shift(changed[:hands][p].length) }
changed[:draw_pile].reverse!;changed[:seed]='f'*32
before=NinetyNinePlanning::WorldSampler.new(game,state,actor).sample(1)
after=NinetyNinePlanning::WorldSampler.new(game,changed,actor).sample(1)
assert(before[:hands]==after[:hands] && before[:draw_pile]==after[:draw_pile], 'fair Ninety-Nine world leaks the actual hidden deal')
omniscient=NinetyNinePlanning::WorldSampler.new(game,state,actor,omniscient:true).sample(1)
assert(omniscient[:hands]==state[:hands],'omniscient Ninety-Nine retains known hands')
changed=Marshal.load(Marshal.dump(state));changed[:draw_pile].reverse!
assert(omniscient[:draw_pile]==NinetyNinePlanning::WorldSampler.new(game,changed,actor,omniscient:true).sample(1)[:draw_pile], 'omniscience must not reveal future random draws')

game=GameRoomGames::Tysiac.new
repository=NewGames116Repository.new(%w[A B C]);session={'options'=>JSON.generate(game.default_options)}
events=[{'id'=>1,'actor'=>'A','action'=>'deal','value'=>'1|0|000102030405060708090a0b0c0d0e0f'},
  {'id'=>2,'actor'=>'B','action'=>'bid','value'=>'100'}, {'id'=>3,'actor'=>'C','action'=>'bid','value'=>'pass'},
  {'id'=>4,'actor'=>'A','action'=>'bid','value'=>'pass'}]
r=game.replay(session,events,repository);talon=r.state[:talon].dup
%w[A C].each do |recipient|
  card=(r.state[:hands]['B']-talon).first
  events << {'id'=>events.length+1,'actor'=>'B','action'=>'pass_card','value'=>"#{recipient}|#{card}"}
  r=game.replay(session,events,repository)
end
events << {'id'=>events.length+1,'actor'=>'B','action'=>'contract','value'=>'100'}
r=game.replay(session,events,repository)
planner=TysiacPlanning::Planner.new(game,r,'A',GameRoomRandom::SeededSource.new(212))
worlds=planner.send(:sampled_worlds,48)
assert(worlds.length==48,'public knowledge must not starve the production sampler')
assert(worlds.all? { |w| (w[:hands]['C'] & talon).length<=1 },'a defender cannot receive two public talon cards through one pass')
puts 'Audit 212: information isolation, 7 card profiles, both poker variants and 48 valid Tysiac worlds passed'
