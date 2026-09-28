require_relative 'support/audit_212_rules_and_decisions'

players = %w[A B]
repo = NewGames116Repository.new(players)
chess = GameRoomGames::Chess.new
state = chess.send(:initial_state, players)
sequence = [[[0,1],[0,3]]] + Array.new(2) { [[[6,7],[5,5]], [[6,0],[5,2]], [[5,5],[6,7]], [[5,2],[6,0]]] }.flatten(1)
sequence.each_with_index do |(from, to), i|
  actor = state[:current_player]
  move = chess.send(:legal_moves, state, actor).find { |m| m.from == from && m.to == to }
  assert(move, 'legal chess repetition fixture')
  chess.send(:apply_chess_move!, state, move, actor)
  chess.send(:finish_chess_turn!, state, actor, i + 1, [])
end
assert(state[:draw], 'uncapturable en passant must not postpone threefold repetition')
other = Marshal.load(Marshal.dump(state)); other[:halfmove] += 1
assert(chess.bot_search_key(audit_replay(state), 'A') != chess.bot_search_key(audit_replay(other), 'A'), 'clock matters to search')

checkers = GameRoomGames::Checkers.new
[true, false].each do |deferred|
  rules = GameRoomGames::Checkers::CLASSIC_RULES
  rules &= ~GameRoomGames::Checkers::DEFER_CAPTURE_REMOVAL unless deferred
  st = checkers.send(:initial_state, players, checkers.normalize_options('board_size' => 10, 'rules' => rules))
  st[:board] = Array.new(10) { Array.new(10) }
  st[:board][4][4] = '0k'; st[:board][6][6] = '1m'; st[:board][2][2] = '1m'
  move = checkers.send(:moves_for_state, st, 'A').find { |m| m.from == [4,4] && m.to == [7,7] }
  assert(move, 'checkers first jump')
  checkers.send(:apply_move!, st, move, 'A')
  reverse = checkers.send(:moves_for_state, st, 'A').any? { |m| m.to == [1,1] }
  assert(reverse != deferred, 'capture blockers must follow the configured variant')
  clone = checkers.send(:duplicate_state, st)
  clone[:capture_blockers] << [1,1]
  assert(!st.fetch(:capture_blockers, []).include?([1,1]), 'simulation must not mutate blockers in its parent')
end

spades = GameRoomGames::Spades.new
bad = spades.normalize_options('team_size' => 2, 'suicide' => true, 'no_hell' => true)
assert(spades.options_error(bad, player_count: 4), 'reject incompatible variants')
%w[suicide no_hell].each do |disabled|
  assert(spades.options_error(bad.merge(disabled => false), player_count: 4).nil?, 'each variant remains independently available')
end
ss = { players: %w[A B C D], hands: {'A' => %w[9S TS JS QS KS AS 2C 3C 4C 5C 6C 7C 8C]},
  options: spades.default_options, bids: {}, scores: %w[A B C D].to_h { |p| [p, 0] } }
allowed = spades.send(:undominated_bot_bids, ss, 'A', (0..13).to_a)
assert(!allowed.include?(5) && allowed.include?(6), 'do not underbid six guaranteed trumps')
sp = audit_replay(ss)
sp.accepted_events << {'action'=>'deal'}
sp.accepted_events << {'action'=>'play','actor'=>'A','value'=>'2S'}
sp.accepted_events << {'action'=>'play','actor'=>'B','value'=>'2C'}
voids = spades.send(:bot_public_play_context, sp)[:void_suits]
assert(!voids['B'].include?('S'), 'withholding a lone ace is not proof of no spades')
planner = spades.send(:spades_round_planner)
assert(planner.send(:hidden_card_allowed?, voids, 'B', 'AS'), 'the ace remains possible')
assert(!planner.send(:hidden_card_allowed?, voids, 'B', 'KS'), 'other spades cannot have been withheld')

makao = GameRoomGames::Makao.new
%w[5 6 7 8 9 T].each do |rank|
  [false, true].each do |joker|
    st = makao.send(:initial_state, players, makao.normalize_options('profile'=>'custom', 'jokers'=>true, 'jack_requests_rank'=>true))
    card = joker ? 'X1' : 'JH'
    choice = joker ? "JH:#{rank}" : rank
    st.update(phase: :playing, current_player:'A', discard:['TH'], declared_suit:'H', hands:{'A'=>[card,'5C','5D'],'B'=>['6C']})
    assert(makao.send(:card_choices_for, st, card).include?(choice), 'requested rank available in the UI')
    event = {'id'=>1,'action'=>'play','actor'=>'A','value'=>"#{card}|#{choice}"}
    assert(makao.send(:apply_play, st, event, 'A', repo, []), 'jack request accepted without an exception')
    assert(st[:requested_rank] == rank, 'joker must use the entire jack effect')
  end
end

uno = GameRoomGames::Uno.new
st = uno.send(:initial_state, players, uno.normalize_options('deck'=>'no_mercy'))
st.update(phase: :playing, current_player:'A', round:1, colour:'R', discard:['R5a'], hands:{'A'=>%w[RAa R1a R2a RDa],'B'=>%w[Y3a Y4a Y6a]})
r = audit_replay(st)
best = uno.legal_actions(r,'A').max_by { |a| uno.bot_action_score(r,'A',a) }
assert(best['card'] == 'RAa', 'Discard All must beat a nonwinning attack')

poker = GameRoomGames::Poker.new
ps = poker.send(:initial_state, %w[A B C], poker.default_options)
ps.update(phase: :betting, community:%w[AS KS QS JS TS], hands:{'A'=>%w[2C 3C],'B'=>%w[2D 3D],'C'=>%w[4C 5C]},
  contributions:{'A'=>1,'B'=>1,'C'=>1}, folded:{'C'=>true}, stacks:{'A'=>100,'B'=>100,'C'=>100}, dealer_index:0)
poker.send(:showdown, ps, 1, [])
assert(ps[:stacks] == {'A'=>101,'B'=>102,'C'=>100}, 'odd chip starts to the left of the dealer')
equities = [2,6].map do |count|
  seated = Array.new(count) { |i| ('A'.ord + i).chr }
  ps = poker.send(:initial_state, seated, poker.normalize_options('variant'=>'draw'))
  ps[:hands]['A'] = %w[AH AD KS 2D 3C]
  unseen = poker.send(:standard_deck) - ps[:hands]['A']
  seated.drop(1).each { |p| ps[:hands][p] = unseen.shift(5) }
  poker.send(:poker_exchange_value, ps, 'A', %w[2D 3C])
end
assert(equities[1] < equities[0], 'draw equity is not heads-up equity against five opponents')

ludo = GameRoomGames::Ludo.new
ls = ludo.send(:initial_state, players, ludo.default_options)
ls.update(pawns:[[14,-1,-1,-1],[50,-1,-1,-1]])
assert(ludo.send(:exposure_risk, ls, 0, 14) == 0, 'a pawn entering home cannot capture on the outer track beyond it')

puts 'Audit 212: rule and decision regressions passed'
