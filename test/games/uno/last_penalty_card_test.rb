require_relative '../../support/new_games_fixture'

game=GameRoomGames::Uno.new
repository=NewGames116Repository.new(%w[Alice Bob Carol])
def terminal_uno_state(game,card,options={})
  state=game.send(:initial_state,%w[Alice Bob Carol],game.normalize_options({'thinking_time'=>0}.merge(options)))
  state.update(phase: :playing,round:1,current_player:'Alice',colour:'R',discard:['R5a'],
    hands:{'Alice'=>[card],'Bob'=>%w[G7a B3a],'Carol'=>%w[Y1a G2a]},
    draw_pile:%w[R1a R2a R3a R4a Y5a Y6a B7a B8a])
end
def apply_terminal_uno(game,state,repository,history,actor,action,value,id)
  event={'id'=>id,'actor'=>actor,'action'=>action,'value'=>value}
  game.send(:apply_replay_event,state,event,{},repository,history)
end

[['RDa',2],['NF0',4]].each do |card,count|
  [false,true].each do |skip|
    state=terminal_uno_state(game,card,'skip_after_penalty'=>skip)
    history=[]
    assert(apply_terminal_uno(game,state,repository,history,'Alice','play',"#{card}||0",1),'Last card rejected')
    if card=='NF0'
      assert(state[:phase]==:playing && state[:colour_choice_player]=='Alice','Wild colour must still be chosen')
      assert(apply_terminal_uno(game,state,repository,history,'Alice','choose_colour','R|0',2),'Colour rejected')
    end
    assert(state[:phase]==:playing && state[:pending_draw]==count && state[:hands]['Alice'].empty?,'Round ended before paying the penalty')
    old_hand=state[:hands]['Bob'].dup
    assert(apply_terminal_uno(game,state,repository,history,'Bob','draw','0',3),'Penalty draw rejected')
    assert(state[:hands]['Bob'].size==old_hand.size+count,'Penalty cards were not actually drawn')
    assert(state[:hands]['Alice'].empty?,'Finisher had to draw another card')
    assert(state[:phase]==:round_complete,'Round did not end immediately after paying the penalty')
    assert(state[:scores]['Bob']==state[:hands]['Bob'].sum { |item|game.send(:card_points,item) },'Scoring omitted the penalty cards')
    assert(history.index { |item|item.kind==:draw } < history.index { |item|item.kind==:round_result },'Result preceded the penalty')
  end
end

# A stacked penalty can return to the empty-handed first finisher. If that
# player must draw, the next empty hand becomes the actual round finisher.
state=terminal_uno_state(game,'RDa')
state[:hands]['Bob']=['GDa']
state[:hands]['Carol']=['BDa']
history=[]
[['Alice','RDa'],['Bob','GDa'],['Carol','BDa']].each_with_index do |(actor,card),index|
  assert(apply_terminal_uno(game,state,repository,history,actor,'play',"#{card}||0",index+1),'Stacked last penalty rejected')
end
assert(state[:pending_draw]==6 && state[:current_player]=='Alice','Stacked penalty did not return to the finisher')
assert(apply_terminal_uno(game,state,repository,history,'Alice','draw','0',4),'Returned penalty rejected')
assert(state[:hands]['Alice'].size==6,'Returned penalty must still be paid')
assert(state[:phase]==:round_complete,'Another empty-handed finisher was forgotten after the first finisher drew')
assert(history.any? { |item|item.kind==:round_result && item.actor=='Bob' },'Wrong winner after penalty returned to the first finisher')

# No Mercy can eliminate the original finisher while paying a returned
# penalty. That must not erase another already empty hand from the queue.
state=terminal_uno_state(game,'RDa','deck'=>'no_mercy','no_mercy_limit'=>10)
state[:hands]['Bob']=['GXa']
state[:hands]['Carol']=['BXa']
state[:draw_pile].concat(%w[B1a B2a B4a B5a Y3a Y4a])
history=[]
[ ['Alice','RDa'], ['Bob','GXa'], ['Carol','BXa'] ].each_with_index do |(actor,card),index|
  assert(apply_terminal_uno(game,state,repository,history,actor,'play',"#{card}||0",index*2+1),'No Mercy last penalty rejected')
end
assert(state[:pending_draw]==10 && state[:current_player]=='Alice','No Mercy penalty did not return to the first finisher')
assert(apply_terminal_uno(game,state,repository,history,'Alice','draw','0',7),'No Mercy returned penalty rejected')
assert(state[:round_eliminated]['Alice'],'The original finisher did not reach the No Mercy limit')
assert(state[:phase]==:round_complete,'No Mercy elimination forgot another empty hand')
assert(history.any? { |item|item.kind==:round_result && item.actor=='Bob' },'Wrong winner after No Mercy elimination')
puts 'PASS UNO last penalty cards: two/four, delayed colour, both skip options, penalty scoring, stacked return and No Mercy elimination'
