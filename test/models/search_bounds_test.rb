require_relative "../support/audit_212_rules_and_decisions"

BoundReplay = Struct.new(:state) { def finished?; false; end }
class BoundEnvironment
  attr_reader :replay
  TREE = {'X'=>%w[a b], 'a'=>%w[a1 a2], 'b'=>%w[b1 b2]}.freeze
  def initialize(node); @replay=BoundReplay.new(node); end
  def active_actor; @replay.state=='X' ? 'A' : 'B'; end
  def legal_actions(_actor); TREE.fetch(@replay.state,[]).map { |n| {'node'=>n} }; end
  def fork_for_search; self.class.new(@replay.state); end
  def step_for_search(action,actor:); @replay=BoundReplay.new(action['node']); :ok; end
end
class BoundGame
  def bot_search_key(r,_a); r.state; end
  def bot_position_value(r,_a); {'a1'=>5,'a2'=>1,'b1'=>4,'b2'=>0}.fetch(r.state,0); end
  def bot_allied?(_r,a,b); a==b; end
  def bot_action_score(*,**); 0; end
  def bot_action_key(a); a['node']; end
end
[false,true].each do |optimized|
  search=GameRoomBots::AlphaBetaStrategy.new(max_depth:2,node_limit:100,optimize_transpositions:optimized)
  search.instance_variable_set(:@search_cache_hits,0)
  search.instance_variable_set(:@search_cutoffs,0)
  cache={}; order={}; game=BoundGame.new
  query=lambda do |alpha,beta,table|
    search.send(:search,BoundEnvironment.new('X'),2,alpha,beta,'A',game,nil,
      GameRoomBots::SearchBudget.new(limit:100),table,order)
  end
  query.call(10,Float::INFINITY,cache)
  assert(query.call(-Float::INFINITY,Float::INFINITY,cache)==1,'an upper bound is not an exact transposition')
  cache.clear
  query.call(-Float::INFINITY,0,cache)
  assert(query.call(-Float::INFINITY,Float::INFINITY,cache)==1,'a lower bound is not an exact transposition')
end

class ContinuationEnvironment < BoundEnvironment
  def active_actor; %w[X a].include?(@replay.state) ? 'A' : 'B'; end
end
class ContinuationGame < BoundGame
  def bot_forced_continuation?(replay); replay.state=='a'; end
  def bot_position_value(r,_a); {'a'=>-100,'b'=>3,'a1'=>5,'a2'=>6}.fetch(r.state,0); end
end
search=GameRoomBots::AlphaBetaStrategy.new(max_depth:1,node_limit:100)
env=ContinuationEnvironment.new('X'); game=ContinuationGame.new
# Exercise root search directly to isolate the continuation contract.
search.instance_variable_set(:@search_cache_hits,0); search.instance_variable_set(:@search_cutoffs,0)
choice=search.send(:root_search,env,env.legal_actions('A'),'A',game,nil,1,
  GameRoomBots::SearchBudget.new(limit:100),{},{},nil)
assert(choice['node']=='a','finish a mandatory continuation before evaluating the position')

chess=GameRoomGames::Chess.new
state=chess.send(:initial_state,%w[A B])
state[:board]=Array.new(8){Array.new(8)}
state[:board][0][0]='wK';state[:board][7][7]='bK';state[:board][6][1]='wP'
state[:castling]='';state[:positions]={};state[:halfmove]=0
move=chess.send(:legal_moves,state,'A').find { |m| m.from==[1,6] && m.to==[1,7] }
chess.send(:apply_chess_move!,state,move,'A')
r=audit_replay(state)
assert(chess.bot_forced_continuation?(r),'promotion remains part of the pawn move')
tactical=chess.bot_tactical_actions(r)
assert(tactical[:forced] && tactical[:actions].map { |a| a['card'] }.sort==%w[B N Q R], 'search sees every promotion including underpromotions')

state=chess.send(:initial_state,%w[A B]); state[:board]=Array.new(8){Array.new(8)}
state[:board][0][0]='wK';state[:board][7][7]='bK';state[:board][0][6]='wR';state[:castling]=''
move=chess.send(:legal_moves,state,'A').find { |m| m.from==[6,0] && m.to==[6,7] }
chess.send(:apply_chess_move!,state,move,'A');history=[]
chess.send(:finish_chess_turn!,state,'A',1,history)
assert(history.count { |entry| entry.kind==:check }==1,'check announced once')
tactical=chess.bot_tactical_actions(audit_replay(state))
assert(tactical[:forced] && !tactical[:actions].empty?,'the search may not stand still in check')

# A quiet-looking capture at the depth boundary must allow the immediate
# recapture. Use the real serialized move, not an invented coordinate format.
state=chess.send(:initial_state,%w[A B]); state[:board]=Array.new(8){Array.new(8)}
state[:board][0][0]='wK';state[:board][7][7]='bK'
state[:board][2][2]='wQ';state[:board][3][3]='bP';state[:board][4][4]='bP'
state[:castling]=''
move=chess.send(:legal_moves,state,'A').find { |m| m.from==[2,2] && m.to==[3,3] }
assert(move,'legal recapture fixture')
chess.send(:apply_chess_move!,state,move,'A');chess.send(:finish_chess_turn!,state,'A',7,[])
r=audit_replay(state);r.accepted_events << {'id'=>7,'action'=>chess.board_event_action,'value'=>move.event_value}
tactical=chess.bot_tactical_actions(r)
assert(!tactical[:forced] && tactical[:actions].any? { |a| a['from_x']==4 && a['from_y']==4 && a['to_x']==3 && a['to_y']==3 },'include legal recapture at the horizon')

checkers=GameRoomGames::Checkers.new
state=checkers.send(:initial_state,%w[A B],checkers.default_options)
r=audit_replay(state);before=checkers.bot_search_key(r,'A')
current=checkers.send(:position_key,state)
state[:positions][current]=2
assert(before!=checkers.bot_search_key(r,'A'),'do not merge distinct reachable repetition counts')
with_current=checkers.bot_search_key(r,'A')
state[:positions]['A:'+('0m'*60)]=2
assert(with_current==checkers.bot_search_key(r,'A'),'more pieces than now can never recur after a capture')
puts 'Audit 212: transposition bounds and forced continuations passed'
