require_relative "../../support/ui"
require_relative "../../support/elten_array_shuffle"
require_relative "../../../lib/game_surfaces"
require_relative "../../../lib/game_random"
require_relative "../../../games/scrabble"
def assert(value, message); raise message unless value; end
def n_(a,b,n); n == 1 ? a : b; end
Repo = Struct.new(:players) do
  def players_for(_session); players; end
  def actor_of(event,_session); event["actor"]; end
  def event_id(event); event["id"]; end
end
game, rules = GameRoomGames::Scrabble.new, GameRoomScrabbleRules
def options_for(game, language)
  game.normalize_options(GameRoomContent::LANGUAGE_OPTION_KEY => language)
end
%w[en pl-PL].each do |language|
  options = options_for(game, language)
  assert(!game.validation_error(options, player_count: 4), "dictionary validation #{language}")
  state = game.initial_state(%w[Alice Bob], options)
  assert(game.tiles(state).length == 100 && game.tiles(state).count { |t| t[:letter].empty? } == 2, "100 tiles / blanks #{language}")
  words = language == "en" ? %w[qi za cat colour] : %w[kot żółć źrebak]
  words.each { |word| assert(game.dictionary(state).include?(word), "missing #{word}") }
  assert(!game.dictionary(state).include?("zxzxzxzxzxzx"), "nonsense accepted")
  assert(!game.dictionary(state).include?("cat dog"), "two words accepted")
end
options = options_for(game,"en")
assert(!game.supports_bots?, "no bots")
assert(game.effective_option_definitions.first.key == GameRoomContent::LANGUAGE_OPTION_KEY, "language first")
set = game.effective_option_definitions.find { |d| d.key == GameRoomContent::SET_OPTION_KEY }
assert(!game.option_visible?(set, options), "redundant set selector")
assert(game.rule_book.documents.length == 2, "rules and shortcuts")

state = game.initial_state(%w[Alice Bob], options)
tiles, alphabet = game.tiles(state), game.language(state).alphabet
def rack_for(tiles, letters)
  available = tiles.each_index.to_a
  letters.chars.map do |letter|
    id = available.find { |i| tiles[i][:letter] == (letter == '?' ? '' : letter) }
    raise "no tile #{letter}" unless id
    available.delete(id)
    id
  end
end
board = Array.new(225)
rack = rack_for(tiles,"catdogs")
placement = rack.first(3).each_with_index.map { |id,i| [id,111+i,tiles[id][:letter]] }
result = rules.evaluate(board,rack,tiles,placement,alphabet)
assert(!result.error && result.score == 10, "CAT at center = 10")
assert(board.compact.empty?, "preview mutated board")
assert(rules.evaluate(board,rack,tiles,placement.map { |id,pos,l| [id,pos-15,l] },alphabet).error == :cover_center, "center mandatory")
assert(rules.evaluate(board,rack,tiles,[placement[0],placement[2]],alphabet).error == :gap_in_word, "gap")
assert(rules.evaluate(board,rack,tiles,[placement[0],[rack[1],127,'a']],alphabet).error == :one_line_required, "diagonal")
assert(rules.evaluate(result.board,rack,tiles,placement,alphabet).error == :occupied_square, "old tile replacement")
extension = rules.evaluate(result.board,[rack.last],tiles,[[rack.last,114,'s']],alphabet)
assert(extension.words.map { |w| w[:word] } == ["cats"] && extension.score == 6, "old center bonus reused")
blanks = rack_for(tiles,"??")
zero = rules.evaluate(board,blanks,tiles,[[blanks[0],112,'a'],[blanks[1],113,'a']],alphabet)
assert(zero.score == 0 && zero.board[112][:blank], "blank zero")
sevens = rack_for(tiles,"retains")
seven = rules.evaluate(board,sevens,tiles,sevens.each_with_index.map { |id,i| [id,109+i,tiles[id][:letter]] },alphabet)
assert(seven.score == seven.words.sum { |w| w[:score] } + 50, "bingo")
# Parallel placement creates every cross word, not only the main word.
parallel_rack = rack_for(tiles,"at")
parallel = rules.evaluate(result.board,parallel_rack,tiles,[[parallel_rack[0],96,'a'],[parallel_rack[1],97,'t']],alphabet)
assert(parallel.words.length == 3, "parallel crosswords")

def playing(game, options, letters = "catdogs")
  state = game.initial_state(%w[Alice Bob], options)
  state.merge!(phase: :playing,current_player: "Alice",turn: 1,revision: 1,turn_started: 100,
    racks: {"Alice" => rack_for(game.tiles(state),letters), "Bob" => rack_for(game.tiles(state),"ex")})
  state
end
def apply(game,state,action,**args)
  history = []
  data = {"action" => action,"revision" => state[:revision],"time" => 101}.merge(args.transform_keys(&:to_s))
  [game.send(:apply,state,data,"Alice",10,history),history]
end
(0..5).each do |policy|
  state = playing(game,options.merge("invalid_word" => policy.to_s),"qx")
  ids = state[:racks]["Alice"]
  draft = ids.each_with_index.map { |id,i| [id,112+i,game.tiles(state)[id][:letter]] }
  status,history = apply(game,state,"place",placements: draft)
  assert(status == :ok && state[:board].compact.empty?, "bad word rollback #{policy}")
  assert(state[:scores]["Alice"] == -[0,0,5,5,10,10][policy], "penalty #{policy}")
  assert(state[:current_player] == (policy.odd? ? "Bob" : "Alice"), "bad word turn #{policy}")
end
[7,8].each do |count|
  state = playing(game,options)
  state[:bag] = (50...50+count).to_a
  status,_ = apply(game,state,"exchange",tiles: state[:racks]["Alice"].first(2), seed: '0'*32)
  assert(status == (count == 7 ? :exchange_unavailable : :ok), "bag exchange boundary")
  assert(state[:bag].length == count, "exchange count")
end
state = playing(game,options)
state[:racks] = {"Alice" => rack_for(game.tiles(state),"cat"),"Bob" => rack_for(game.tiles(state),"x")}
state[:scores] = {"Alice" => 0,"Bob" => 100}
ids = state[:racks]["Alice"]
apply(game,state,"place",placements: ids.each_with_index.map { |id,i| [id,111+i,game.tiles(state)[id][:letter]] })
assert(state[:scores] == {"Alice" => 18,"Bob" => 92} && state[:winner] == "Bob", "finisher need not win")
state = playing(game,options)
state[:idle_turns] = 5
apply(game,state,"pass")
assert(state[:phase] == :finished && state[:scores]["Alice"] < 0, "blocked final adjustment")
state = playing(game,options.merge("thinking_time" => 20))
state[:turn_deadline] = 101
assert(apply(game,state,"place",placements: placement).first == :invalid, "deadline prevents placement")
assert(apply(game,state,"timeout").first == :ok && state[:current_player] == "Bob", "timeout")

repo = Repo.new(%w[Alice Bob Carol Dora])
session = { "options" => JSON.generate(options) }
replay = game.replay(session,[],repo)
context = GameRoomGames::ActionContext.new(random_source: GameRoomRandom::SeededSource.new(4),now: 100)
status,plan = game.action_for({"action" => "deal"},replay,"Alice",context: context)
assert(status == :ok && plan.events.all? { |e| e.value.length <= 64 }, "deal wire")
events = plan.events.each_with_index.map { |e,i| {"id"=>i+1,"actor"=>"Alice","action"=>e.action,"value"=>e.value} }
replay = game.replay(session,events,repo)
assert(replay.state[:bag].length == 72 && replay.state[:racks].values.flatten.uniq.length == 28, "four player deal")
assert(game.replay(session,events+events,repo).state == replay.state, "idempotent replay")
assert(game.replay(session,events[0...-1],repo).state[:phase] == :awaiting_deal, "partial move atomic")
assert(game.game_shortcuts(replay,"Alice").any? { |s| s.key == 'backspace' }, "Backspace binding")
pl_replay = game.replay(session.merge('options' => JSON.generate(game.default_options)), [], repo)
pl_shortcuts = game.game_shortcuts(pl_replay, 'Alice')
assert(pl_shortcuts.none? { |s| s.payload.is_a?(Hash) && s.payload.key?('letter') }, 'obsolete letter-placement shortcuts still present')
assert((1..7).all? { |number| pl_shortcuts.any? { |s| s.key == number.to_s && s.action_name == 'word_read' } }, 'rack position read shortcuts missing')
puts "Scrabble rules, dictionaries, replay and boundaries passed."
