require_relative "../support/audit_212_rules_and_decisions"
require_relative "../../games/reversi"
require_relative "../../games/four_in_a_row"
require_relative "../../lib/game_simulation"

def choose_audit(game, state, actor)
  r = audit_replay(state)
  game.bot_strategy.choose(actions:game.legal_actions(r,actor),actor:actor,game:game,replay:r,
    random_source:GameRoomRandom::SeededSource.new(212))
end

farkle = GameRoomGames::Farkle.new
# Under the current final-circuit rule reaching the limit is only a certain
# victory for the last seat. A first-seat threshold crossing leaves a reply.
st = farkle.send(:initial_state,%w[B A],farkle.normalize_options('score_limit'=>1000,'entry_minimum'=>0,'turn_minimum'=>0))
st.update(phase: :selecting,current_player:'A',last_roll:[1,2,2,2,5,6],turn_points:0,dice_to_roll:6)
st[:scores]['A']=970
choice=choose_audit(farkle,st,'A')
assert(farkle.bot_keep_details(audit_replay(st),choice)[:points]>=30,'Farkle must choose any certain winning keep')

yahtzee=GameRoomGames::Yahtzee.new
ys=yahtzee.send(:initial_state,%w[A B],yahtzee.default_options)
cats=yahtzee.send(:categories,ys)
ys[:sheets]=%w[A B].to_h { |p| [p,cats.to_h { |c| [c,0] }] }
ys[:sheets]['B'].delete('chance'); ys[:sheets]['A']['chance']=20
ys.update(current_player:'B',turn_rolls:2,dice:[3,3,3,6,6])
assert(choose_audit(yahtzee,ys,'B')['action']=='score','Yahtzee must bank the certain last-turn victory')
assert(yahtzee.send(:bot_upper_bonus_probability,[],1)==0,'unreachable upper bonus')
assert(yahtzee.send(:bot_upper_bonus_probability,[],0)==1,'secured upper bonus')
assert(yahtzee.send(:bot_upper_bonus_probability,[5],31)==0,'five sixes cannot produce 31')
assert(yahtzee.send(:bot_upper_bonus_probability,[5],18)>yahtzee.send(:bot_upper_bonus_probability,[5],30),'bonus probability respects attainable threshold')

nn=GameRoomGames::NinetyNine.new
orders=(1..5).map do |seed|
  state={draw_pile:[],discard:%w[2C 3C 4C 5C 6C 7C],planning_seed:seed,planning_recycles:0}
  NinetyNinePlanning::Transition.refill_draw_pile(state)
  assert(state[:draw_pile].sort==%w[2C 3C 4C 5C 6C],'recycling preserves all cards except the top')
  state[:draw_pile]
end
assert(orders.uniq.length>1,'different information-set worlds do not share one fake future shuffle')

makao=GameRoomGames::Makao.new
ms=makao.send(:initial_state,%w[A B C],makao.normalize_options('profile'=>'custom','jokers'=>true,'jack_requests_rank'=>true))
ms.update(phase: :playing,current_player:'A',hands:{'A'=>%w[JH 5C 5D X1],'B'=>%w[6S],'C'=>%w[7S]},discard:['TH'],declared_suit:'H',makao_windows:{'B'=>true})
r=audit_replay(ms); before=Marshal.dump(ms)
scores=makao.legal_actions(r,'A').map { |a| [a,makao.bot_action_score(r,'A',a)] }
assert(Marshal.dump(ms)==before,'Makao evaluation must not consume waiting turns or declaration windows')
jack=scores.select { |a,_| JSON.parse(a['cards'].to_s) == ['JH'] rescue false }.to_h { |a,s| [a['choice'],s] }
assert(jack['5']>jack['6'],'ask for the rank held in the remaining hand')
[['JH','X1'],['X1','JH'],['X1']].each do |cards|
  assert(makao.send(:validate_packet,ms,'A',cards,'JH:5')==:ok,'mixed joker/jack packet must keep the request')
end

poker=GameRoomGames::Poker.new
ps=poker.send(:initial_state,%w[A B C],poker.default_options)
ps.update(phase: :betting,community:%w[AS KS QS JS TS],hands:{'A'=>%w[2C 3C],'B'=>%w[2D 3D],'C'=>%w[4C 5C]},contributions:{'A'=>10,'B'=>1000,'C'=>1000})
expected=poker.send(:poker_pot_expectation,ps,'A',ps[:contributions],{})
assert((expected-10).abs<0.0001,'short stack cannot win the 1980-chip side pot')
ps[:folded]['C']=true
assert((poker.send(:poker_pot_expectation,ps,'A',ps[:contributions],{})-15).abs<0.0001,'folded chips stay, folded hands do not compete')
assert(poker.send(:poker_model_discards,%w[AH AD 2C 3C 4C],3).sort==%w[2C 3C 4C],'draw opponent model preserves a pair')
assert(poker.send(:poker_model_discards,%w[2H 3H 4H 5H 6H],5).empty?,'draw opponent does not break a made straight flush')
exchange=poker.send(:initial_state,%w[A B C D E F],poker.normalize_options('variant'=>'draw'))
exchange.update(phase: :exchange,current_player:'A')
exchange[:hands]['A']=%w[AH AD KS 2D 3C]
deck=poker.send(:standard_deck)-exchange[:hands]['A']
exchange[:players].drop(1).each { |player| exchange[:hands][player]=deck.shift(5) }
draw_choice=choose_audit(poker,exchange,'A')
assert(JSON.parse(draw_choice['cards']).sort==%w[KS 2D 3C].sort,
  'sampling noise should not preserve a weak singleton instead of improving a pair')
# A clear alternative still beats the standard pair strategy: do not lock the
# bot into a table of rules when the same worlds provide decisive evidence.
exchange[:hands]['A']=%w[AH AD KH QH JH]
prior=poker.send(:poker_model_discards,exchange[:hands]['A'],3)
poker.send(:poker_exchange_value,exchange,'A',prior)
opponent=poker.send(:five_card_rank,%w[2S 3S 4S 5S 6S])
poker.instance_variable_set(:@exchange_samples,Array.new(96) { [%w[TH 2C 3C 4D 5D],[opponent],1.0] })
poker.instance_variable_set(:@exchange_scores,{})
poker.instance_variable_set(:@exchange_outcomes,{})
assert(poker.send(:poker_exchange_value,exchange,'A',['AD'])>poker.send(:poker_exchange_value,exchange,'A',prior),
  'decisive evidence of a better exchange must override the simple prior')

mono=GameRoomGames::Monopoly.new
state=mono.send(:initial_state,%w[A B],mono.default_options)
street=state[:board].find { |s| s[:type]==:property && s[:rents][5]>500 }
state[:owners][street[:index]]='B'; state[:houses][street[:index]]=5
state[:positions]['A']=(street[:index]-7)%state[:board].length
near=mono.send(:monopoly_cash_reserve,state,'A')
state[:positions]['A']=street[:index]
far=mono.send(:monopoly_cash_reserve,state,'A')
assert(near>far,'Monopoly reserve notices an expensive likely landing')
assert((mono.send(:monopoly_landing_probabilities,state)['A'].values.sum-1).abs<1e-9,'36 dice outcomes preserve probability')
utility=state[:board].find { |s| s[:type]==:utility };state[:owners][utility[:index]]='A';state[:last_roll]=0
assert(mono.send(:monopoly_expected_rent,state,utility,'A')>0,'future utility income is not the previous zero roll')
state[:options]['no_rent_in_jail']=true;state[:jail]['A']=2
assert(mono.send(:monopoly_expected_rent,state,utility,'A')==0,'respect no-rent-in-jail in the forecast')
state[:jail]['A']=0
group=state[:board].select { |s| s[:type]==:property && s[:group]==street[:group] }
group.each { |s| state[:owners][s[:index]]='A';state[:houses][s[:index]]=5 }
state[:board_data]=state[:board_data].merge(bank_houses:0)
proceeds,loss=mono.send(:monopoly_liquidation_effect,state,'A',street,'sell')
assert(proceeds==group.sum { |s| s[:house_cost]*5/2 } && loss>=0,'hotel liquidation estimates the entire required group, not just one house')

chess=GameRoomGames::Chess.new
state=chess.send(:initial_state,%w[A B]); state[:board]=Array.new(8){Array.new(8)}
state[:board][0][4]='wK';state[:board][7][4]='bK'
edge=chess.bot_position_value(audit_replay(state),'A')
state[:board][0][4]=nil;state[:board][3][4]='wK'
assert(chess.bot_position_value(audit_replay(state),'A')>edge,'king centralization is useful in a bare-king ending')
# Pinned en passant is not a legal right for repetition purposes.
state[:board]=Array.new(8){Array.new(8)}
state[:board][0][4]='wK';state[:board][7][0]='bK';state[:board][7][4]='bR'
state[:board][4][4]='wP';state[:board][4][3]='bP';state[:en_passant]=[3,5]
with_ep=chess.send(:position_key,state)
state[:en_passant]=nil
assert(chess.send(:position_key,state)==with_ep,'pinned en passant cannot distinguish repeated positions')

rev=GameRoomGames::Reversi.new
board=Array.new(8){Array.new(8)};board[0][0..3]=[0,0,0,1];board[1][0]=0
stable=rev.send(:reversi_stable_edges,board)
assert(stable.sort==[[0,0],[1,0],[2,0],[0,1]].sort,'only same-colour corner-anchored edge chains are certified stable')
puts 'Audit 212: additional strategy features passed'
