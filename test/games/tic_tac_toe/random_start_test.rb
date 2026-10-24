require_relative '../../support/session_runner'
require_relative '../../../games/tic_tac_toe'
include GameRoomTest::Assertions

game=GameRoomGames::TicTacToe.new
starts=[]
[1,2,3,4,5,6].each do |entropy|
  options=game.new_game_options({})
  h=NativeRoomHarness.new(game:game,users:%w[Alice Bob],options:options)
  h.start
  empty=h.replay('Alice')
  assert_equal(nil,empty.current_player,'A move was allowed before the start draw')
  assert_equal([],game.legal_actions(empty,'Alice'))
  assert_equal(:playing,empty.state[:phase],'The new start metadata lost the shared game phase')
  assert_equal(%w[Alice Bob],game.tournament_active_players(empty,options:options))
  h.view('Alice').next_random_values=Array.new(16,entropy)
  h.submit('Alice')
  current=h.replay('Alice')
  assert(current.current_player && current.accepted_events.size==1,'Native start draw was not accepted')
  starts << current.current_player
  assert_equal(1,h.view('Alice').calls[:random],'Start draw bypassed the server or sent extra random requests')
  h.assert_converged('first player drawn',expected_count:1)
  actor=current.current_player
  h.submit(actor,game.legal_actions(current,actor).first)
  moved=h.replay('Bob')
  assert_equal('X',moved.history.last.value,'The drawn starting player must use crosses')
  assert_equal(actor,moved.history.last.actor)
  h.assert_converged('first move',expected_count:2)
  events=h.events('Alice')
  duplicate=events.first.merge('__id'=>events.last['__id']+1,'id'=>events.last['id']+1,'value'=>current.current_player=='Alice' ? '1' : '0')
  assert_equal(moved,game.replay(h.repositories['Alice'].snapshot_for(h.session).session,events+[duplicate],h.repositories['Alice']),
    'A second start draw changed an ongoing game')
  until h.replay('Alice').finished?
    current=h.replay('Alice')
    h.submit(current.current_player,game.legal_actions(current,current.current_player).first)
  end
  assert_equal(:finished,h.replay('Alice').state[:phase],'Shared tournament views did not see completion')
  h.assert_converged('finished random-start game')
end
assert_equal(%w[Alice Bob],starts.uniq.sort,'The draw never lets one of the seats begin')
assert_equal(1,game.table_creation_options({})['random_start'])
assert_equal(1,game.options_from_json(JSON.generate(game.new_game_options({})))['random_start'])
# Archives from before this change retain the original first-seat starter.
repo=Struct.new(:players) do
  def players_for(_);players;end
  def actor_of(event,*);event['actor'];end
  def event_id(event);event['id'];end
end.new(%w[Alice Bob])
old=game.replay({'options'=>'{}'},[{'id'=>1,'actor'=>'Alice','action'=>'place','value'=>'1,1'}],repo)
assert_equal('Bob',old.current_player)
assert_equal(nil,old.state)
assert_equal('X',old.history.last.value)
puts 'PASS tic-tac-toe: both server-drawn starters, one draw, marks, client convergence, duplicate draw refusal and legacy replay'
