require_relative "../support/binary_rules_load" if ARGV.first
require_relative "../support/new_games_fixture"
require_relative "../../games/mexican_train"
require_relative "../../games/domino"
require_relative "../../games/rummy"
require_relative "../../games/scrabble"
require_relative "../../games/ninety_nine"
require_relative "../../lib/game_sounds"

games = [GameRoomGames::Uno, GameRoomGames::Makao, GameRoomGames::Domino,
  GameRoomGames::MexicanTrain, GameRoomGames::Rummy, GameRoomGames::Scrabble,
  GameRoomGames::NinetyNine, GameRoomGames::Poker]
games.each do |type|
  game = type.new
  definitions = game.effective_option_definitions.select { |d| d.key == "thinking_time" }
  assert(definitions.length == 1 && definitions.first.default == 0, "shared opt-in #{game.id}")
  [0, game.thinking_time_range.min, game.thinking_time_range.max].each do |time|
    assert(game.thinking_time_options_error("thinking_time" => time) == nil, "valid range #{game.id}")
  end
  [-1, game.thinking_time_range.max + 1].each do |time|
    assert(game.thinking_time_options_error("thinking_time" => time), "invalid range #{game.id}")
  end
end

game = GameRoomGames::Makao.new
repo = NewGames116Repository.new(%w[A B])
session = { "options" => JSON.generate(game.normalize_options("thinking_time" => 20)) }
events = []
ctx = GameRoomGames::ActionContext.new(now: 100, random_source: NewGames116Random.new)
r = game.replay(session, events, repo)
r = append_action(game, session, repo, events, r, "A", {"kind"=>"command", "action"=>"deal"}, ctx)
assert(r.state[:turn_deadline] == 120 && r.state[:turn_number] == 1, "Makao starts a shared deadline")
assert(r.accepted_events == events && events.all? { |e| e["value"].bytesize <= 64 }, "preserve original wire clock/limit")
ctx.now = 119
assert(!game.automatic_action_due?(r, "A", context: ctx), "not early")
assert(game.action_for({"action"=>"makao_timeout"}, r, "A", context: ctx).first == :invalid, "early timeout rejected")
ctx.now = 120
assert(game.automatic_action_due?(r, "A", context: ctx), "automatic wake at deadline")
assert(game.automatic_action(r, "A", context: ctx)["action"] == "makao_timeout", "owner drives timeout")
assert(game.action_for({"action"=>"makao_timeout"}, r, "B", context: ctx).first == :not_your_turn, "non-owner cannot time out another")
player = r.current_player
hand = r.state[:hands][player].dup
discard = r.state[:discard].dup
r = append_action(game, session, repo, events, r, "A", {"action"=>"makao_timeout"}, ctx)
assert(r.state[:hands][player].length == hand.length + 1 && r.state[:discard] == discard, "draw once, never play")
assert(r.current_player != player && r.state[:turn_deadline] == 140, "pass and give next player full time")
assert(game.replay(session, events + events, repo).state == r.state, "duplicate events ignored")
stale = events.last.merge("id" => 90)
assert(game.replay(session, events + [stale], repo).accepted_events == events, "stale timeout ignored")
assert(game.replay(session.merge("__clock_offset" => 500), events, repo).state[:turn_deadline] == 140, "restore keeps logical deadline")

def timeout_position(game, drawn: false, penalty: 0, skip: 0)
  game.send(:initial_state, %w[A B], game.normalize_options("thinking_time"=>20)).merge(
    phase: :playing, current_player: "B", turn_deadline: 120, turn_started: 100, turn_number: 1,
    hands: {"A"=>%w[5S 6S], "B"=>%w[9H 8S]}, discard: %w[7H], draw_pile: %w[2C 3C 5C 6C],
    declared_suit: "H", drawn_this_turn: drawn, draw_penalty: penalty, skip_penalty: skip)
end
[[true,0,0,1],[false,3,0,3],[false,0,3,0],[false,0,0,1]].each do |drawn, penalty, skip, extra|
  s = timeout_position(game, drawn: drawn, penalty: penalty, skip: skip)
  before = GameRoomGames::Replay.new(players: s[:players], state: Marshal.load(Marshal.dump(s)))
  hist = []
  assert(game.send(:apply_timeout, s, {"id"=>2,"value"=>120.to_s(36)}, "A", repo, hist, 120), "accept Makao timeout scenario")
  assert(s[:hands]["B"].length == 2 + extra && s[:current_player] == "A", "Makao double draw/penalty/skip")
  assert(s[:discard] == %w[7H], "timeout played a card")
  after = GameRoomGames::Replay.new(players: s[:players], state: s, history: hist)
  cue = GameRoomSounds.event_cue(game: game, event: {"id"=>2,"action"=>"makao_timeout"},
    before_replay: before, after_replay: after, repository: repo, viewer: "B")
  assert(Array(cue) == (extra > 0 ? ["draw"] : []), "timeout sound must reflect drawing, not accepting a wait")
end
s = timeout_position(game)
game.send(:refresh_makao_clock, s, "makao", 115)
assert(s[:turn_deadline] == 120, "declaration resets time")
s[:drawn_this_turn] = true
game.send(:refresh_makao_clock, s, "draw", 115)
assert(s[:turn_deadline] == 120, "draw resets time")

# The longest legal packet (four equal ranks and both jokers), including a
# joker jack's extra request and the clock, must still fit a single event.
s = timeout_position(game)
s[:options] = game.normalize_options("profile"=>"custom", "jokers"=>true, "jack_requests_rank"=>true, "thinking_time"=>600)
s[:hands]["B"] = %w[JH JS JC JD X0 X1 9S]
s[:turn_number] = 1_000_000
s[:turn_started] = 2_000_000_000
s[:turn_deadline] = 2_000_000_600
s[:declared_suit] = "H"
r_packet = GameRoomGames::Replay.new(players: s[:players], current_player: "B", state: s)
packet = {"action"=>"play", "cards"=>JSON.generate(s[:hands]["B"].take(6)), "choice"=>"JS:5"}
status, plan = game.action_for(packet, r_packet, "B", context: GameRoomGames::ActionContext.new(now: 2_000_000_100))
assert(status == :ok && plan.events.one? && plan.events.first.value.bytesize <= 64, "timed joker packet exceeds event limit")

uno = GameRoomGames::Uno.new
[[false,0,1],[true,0,1],[true,4,4]].each do |drawn, penalty, extra|
  s = uno.send(:initial_state, %w[A B], uno.normalize_options("thinking_time"=>20))
  s.merge!(phase: :playing, current_player: "B", turn_deadline: 120,
    hands: {"A"=>%w[R2:0 R3:0], "B"=>%w[R5:0 B4:0]}, discard: %w[R4:0],
    draw_pile: %w[B1:0 B2:0 B3:0 B6:0 B7:0], optional_draws: drawn ? 1 : 0, pending_draw: penalty)
  hist = []
  assert(uno.send(:apply_turn_timeout, s, {"id"=>2,"value"=>"1|120|140"}, "A", repo, hist), "UNO timeout scenario")
  assert(s[:hands]["B"].length == 2 + extra && s[:current_player] == "A", "UNO keeps timeout penalty even after a voluntary draw")
  assert(s[:optional_draws] == 0 && s[:discard] == %w[R4:0], "UNO new turn reset, no play")
end

train = GameRoomGames::MexicanTrain.new
[false,true].each do |drawn|
  s = train.initial_state(%w[A B], train.normalize_options("thinking_time"=>20))
  s.merge!(phase: :playing, current_player: "B", turn: 2, round: 1, turn_started: 100, turn_deadline: 120,
    hands: {"A"=>%w[120],"B"=>%w[660]}, stock: %w[160 220], drawn: drawn,
    trains: {"p0"=>{owner:"A",open:false,end:6,chain:[]}, "p1"=>{owner:"B",open:false,end:6,chain:[]}, "m"=>{owner:nil,open:true,end:6,chain:[]}}, pending: ["p0"])
  hist = []
  status = train.send(:apply, s, {"action"=>"timeout","round"=>1,"turn"=>2,"time"=>120}, "A", 2, hist)
  assert(status == :ok && s[:hands]["B"].length == (drawn ? 1 : 2), "train draw exactly once")
  assert(s[:trains]["p1"][:open] && s[:pending] == ["p0"] && s[:current_player] == "A", "train opens, double remains, next turn")
  assert(!s[:voids].key?("B"), "timeout falsely teaches bot a void")
end
puts "PASS shared thinking time: opt-in ranges, Makao authority/clock/replay/restore and packet size, timeout penalties/sounds, UNO penalty preserved, Mexican Train draws once; no automatic card/tile play"
