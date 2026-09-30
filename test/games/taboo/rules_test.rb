require_relative "../../support/ui"
require_relative "../../support/elten_array_shuffle"
require_relative "../../../lib/game_surfaces"
require_relative "../../../games/taboo"
require_relative "../../../lib/game_sounds"
def assert(value,message); raise message unless value; end
def n_(a,b,n); n == 1 ? a : b; end
game = GameRoomGames::Taboo.new
%w[pl-PL en].each do |language|
  options = game.normalize_options(GameRoomContent::LANGUAGE_OPTION_KEY => language)
  assert(!game.validation_error(options,player_count: 4), "valid content #{language}")
  cards = game.selected_content_pack(options).data
  assert(cards.length == 500 && cards.map { |c| c['id'] }.uniq.length == 500, "500 stable IDs")
  assert(cards.map { |c| c['word'].downcase }.uniq.length == 500, "500 targets")
  assert(cards.all? { |c| c['forbidden'].length == 5 && c['forbidden'].uniq.length == 5 }, "five restrictions")
end
assert(!game.supports_bots?,"no bots")
assert(game.rule_book.documents.length == 2,"two rule documents")
[2,3,5,7].each { |n| assert(game.validation_error({},player_count: n),"reject #{n}") }
[4,6,8].each do |n|
  players = Array.new(n) { |i| "P#{i}" }
  state = game.initial_state(players,game.normalize_options("turns_each" => 1))
  assert(state[:teams].map(&:length) == [n/2,n/2],"equal teams")
end
players = %w[Alice Bob Carol Dave]
state = game.initial_state(players,game.normalize_options("turns_each" => 1,"turn_seconds" => 30))
history = []
def apply(game,state,history,action,actor = "Alice",extra = {})
  data = { "action" => action, "revision" => state[:revision], "time" => state[:time]+1, "token" => game.token(state) }.merge(extra)
  game.send(:apply,state,data,actor,state[:revision]+1,history)
end
assert(apply(game,state,history,"deal","Alice",{"seed" => "1"*32}) == :ok,"deal")
assert(state[:phase] == :ready,"ready")
replay_for = -> { GameRoomGames::Replay.new(board: [], players: players, current_player: state[:current_player], winner: state[:winner], draw: false, state: state, history: history, accepted_events: []) }
assert(game.save_game_error(replay_for.call) == nil,"safe save")
assert(apply(game,state,history,"start",state[:current_player]) == :ok,"start")
assert(game.save_game_error(replay_for.call),"cannot save preparation")
assert(apply(game,state,history,"begin","Alice",{"time"=>state[:deadline]-1}) != :ok,"wait three seconds")
assert(apply(game,state,history,"begin","Alice",{"time"=>state[:deadline]}) == :ok,"begin")
deadline, original = state[:deadline], game.token(state)
giver = state[:current_player]
opponent = state[:teams][1-state[:team]].first
guesser = state[:teams][state[:team]].find { |p| p != giver }
assert(game.card_lines(state,giver).length == 6 && game.card_lines(state,opponent).length == 6,"authorized card")
[guesser,"observer"].each do |viewer|
  assert(game.card_lines(state,viewer).empty?,"private card #{viewer}")
  spec = game.surface_spec(replay_for.call,viewer)
  assert(spec.lines.empty?,"safe surface")
  keys = game.game_shortcuts(replay_for.call,viewer).map(&:key)
  assert((keys & %w[c 1 2 3 4 5 6 p b]).empty?,"safe shortcuts")
end
assert(apply(game,state,history,"buzzed",guesser) != :ok,"guesser cannot buzz")
assert(apply(game,state,history,"correct",opponent) != :ok,"opponent cannot guess")
assert(apply(game,state,history,"correct",giver) == :ok,"correct")
assert(state[:deadline] == deadline,"clock unchanged")
assert(apply(game,state,history,"buzzed",opponent,{"token"=>original}) != :ok,"late buzzer cannot score next card")
assert(apply(game,state,history,"skipped",giver) == :ok,"skip")
assert(apply(game,state,history,"buzzed",opponent) == :ok,"buzz")
assert(game.send(:review_points,state) == (state[:team] == 0 ? [1,2] : [2,1]),"provisional scoring")
assert(state[:scores] == [0,0],"scores not committed before review")
words = game.cards(state).values_at(*state[:used]).map { |c| c['word'] }
assert(history.none? { |h| words.any? { |word| h.text.include?(word) } },"active card not leaked in history")
assert(apply(game,state,history,"timeout","Alice",{"time"=>deadline}) == :ok,"timeout")
assert(state[:review].last[:result] == "neutral","unfinished neutral")
assert(game.save_game_error(replay_for.call),"cannot save review")
assert(apply(game,state,history,"correct_result","Bob",{"index"=>0,"result"=>"neutral"}) != :ok,"master only correction")
assert(apply(game,state,history,"correct_result","Alice",{"index"=>0,"result"=>"neutral"}) == :ok,"correction")
assert(apply(game,state,history,"restart_turn") == :ok,"technical restart")
assert(state[:scores] == [0,0] && state[:current_player] == giver && state[:review].empty?,"restart same giver no points")
assert(state[:used].length == 4,"used cards stay used")

# Equal rotation and overtime are decided only after both teams have played.
givers = []
6.times do |turn|
  givers << state[:current_player]
  apply(game,state,history,"start",state[:current_player])
  apply(game,state,history,"begin","Alice",{"time"=>state[:deadline]})
  if turn == 4
    apply(game,state,history,"correct",state[:current_player])
  end
  apply(game,state,history,"timeout","Alice",{"time"=>state[:deadline]})
  apply(game,state,history,"approve")
  assert(state[:phase] == :ready,"no premature victory #{turn}") if turn < 5
end
assert(givers.first(4).sort == players.sort,"each player describes once")
assert(state[:phase] == :finished && state[:completed] == 6,"two overtime turns")
assert(game.bot_reward(replay_for.call,players.find { |p| "team:#{game.team_of(state,p)}" == state[:winner] }) == 1,"team victory")

state[:deck], state[:used], state[:cycle] = [], [], 0
501.times { game.send(:next_card,state) }
assert(state[:used].first(500).uniq.length == 500,"no repeats before exhaustion")
assert(state[:used][-1] != state[:used][-2],"no immediate reshuffle repeat")

Repo = Struct.new(:players) do
  def players_for(_s); players; end
  def actor_of(e,_s); e['actor']; end
  def event_id(e); e['id']; end
end
repo = Repo.new(players)
session = { "options"=>JSON.generate(game.normalize_options({})) }
data = {"action"=>"deal","revision"=>0,"time"=>1,"seed"=>"a"*32}
events = GameRoomActionPayload.commands("taboo",data).each_with_index.map { |c,i| {"id"=>i+1,"actor"=>"Alice","action"=>c.action,"value"=>c.value} }
assert(events.all? { |e| e['value'].length <= 64 },"bounded transport")
assert(game.replay(session,events[0...-1],repo).state[:phase] == :awaiting_deal,"atomic fragments")
assert(game.replay(session,events+events,repo).accepted_events.length == events.length,"retry idempotent")
puts "Taboo content, roles, timing, disputes, rotation, overtime and replay: OK"
