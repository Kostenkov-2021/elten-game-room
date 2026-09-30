if ARGV.delete("--binary")
  require_relative "../support/binary_rules_load"
  BinaryRulesLoad.load(File.expand_path(__FILE__))
  exit
end
require_relative "../support/native_live_sessions"
require_relative "../../lib/game_simulation"
require_relative "../../lib/game_session_clock"
require_relative "../../lib/game_screen"
%w[makao ninety_nine poker domino mexican_train scrabble taboo].each { |name| require_relative "../../games/#{name}" }
def n_(one, many, count); count == 1 ? one : many; end

%w[Makao NinetyNine Poker Domino MexicanTrain].each do |type|
  game = GameRoomGames.const_get(type).new
  [0,30].product([-2,-21_600]).each do |duration, skew|
    players = %w[Alice Bob Charlie].first([game.minimum_players,2].max)
    session = {"__id"=>1,"table_id"=>1,"options"=>JSON.generate(game.normalize_options("thinking_time"=>duration)),"__players"=>players}
    env = GameRoomSimulation::Environment.new(game: game,session: session,events: [],players: players,random_source: GameRoomRandom::SeededSource.new(42))
    env.instance_variable_set(:@test_time, 1_700_000_000)
    def env.context; super.tap { |c| c.now = @test_time }; end
    env.stabilize!
    actor = env.active_actor
    actions = game.legal_actions(env.replay, actor, context: env.context)
    action = actions.find { |a| !%w[pass catch makao].include?(a["action"]) } || actions.first
    assert(action != nil, "missing #{type} fixture action")
    env.instance_variable_set(:@test_time, 1_700_000_000+skew)
    count = env.replay.accepted_events.length
    env.step(action, actor: actor)
    assert(env.replay.accepted_events.length > count, "#{type}/#{duration}: slower clock rejected action")
  end
end

%w[Scrabble Taboo].each do |type|
  game = GameRoomGames.const_get(type).new
  players = %w[Alice Bob Charlie David].first(game.minimum_players)
  state = game.initial_state(players,game.default_options)
  state[:revision], state[:current_player] = 1, players.first
  if type == "Scrabble"
    state[:phase], state[:turn_started] = :playing,1_700_000_000
    selection = {"action"=>"pass"}
  else
    state[:phase], state[:time], state[:team] = :ready,1_700_000_000,0
    selection = {"action"=>"start","token"=>game.token(state)}
  end
  replay = GameRoomGames::Replay.new(players: players,state: state,accepted_events: [],history: [])
  context = GameRoomGames::ActionContext.new(now: 1_699_978_400, table_owner: players.first)
  assert(game.action_for(selection,replay,players.first,context: context).first == :ok, "#{type}: local action not aligned")
  bad = selection.merge("revision"=>1,"time"=>1_699_999_998)
  assert(game.send(:apply,Marshal.load(Marshal.dump(state)),bad,players.first,2,[]) == :invalid, "#{type}: strict wire time removed")
end

state = {options: {"thinking_time"=>30},turn_number: 4,turn_started: 100,turn_deadline: 130}
encoded = GameRoomTurnClock.encode(state,"payload",GameRoomGames::ActionContext.new(now: 98))
assert(GameRoomTurnClock.decode(state,{"value"=>encoded}).last == 100, "encoder regressed behind accepted state")
assert(GameRoomTurnClock.decode(state,{"value"=>"payload~3:#{100.to_s(36)}"}) == nil, "old turn accepted")
assert(GameRoomTurnClock.decode(state,{"value"=>"payload~4:#{99.to_s(36)}"}) == nil, "old wire time accepted")
assert(!GameRoomTurnClock.expired?(state,129) && GameRoomTurnClock.expired?(state,130), "timeout boundary changed")

# Both clients use the same server-derived elapsed time, regardless of their
# wall clocks. No HTTP call is part of this source.
sample, elapsed = 1000, 40.0
session = {"created_at"=>5000,"__server_started_at"=>990,"__clock_offset"=>0}
clocks = [-21_600,21_600].map { |skew| GameRoomSessionClock.new(sample: -> { sample },elapsed: -> { elapsed },wall: -> { 1000+skew }) }
assert(clocks.map { |c| c.now(session) } == [5010,5010], "clients disagree with server time")
elapsed += 20
assert(clocks.map { |c| c.now(session) } == [5030,5030], "stale host timestamp stopped clock")
sample = nil
elapsed += 10
assert(clocks.map { |c| c.now(session) } == [5040,5040], "connection gap discarded clock")
paused = session.merge("__frozen_at"=>1025)
assert(clocks.map { |c| c.now(paused) } == [5035,5035], "pause mixes server and game epochs")
restored = session.merge("__clock_offset"=>4900)
assert(clocks.map { |c| c.now(restored) } == [140,140], "restored logical time changed")
sample = 1031
elapsed += 1
assert(clocks.map { |c| c.now(restored) } == [141,141], "server resampling changed epoch")
screen = GameScreen.allocate
repo = Object.new
repo.define_singleton_method(:session_id) { |_session| 17 }
screen.instance_variable_set(:@repository,repo)
screen.instance_variable_set(:@game,GameRoomGames::Makao.new)
screen.instance_variable_set(:@session,restored.merge("options"=>"{}"))
screen.instance_variable_set(:@table,{"__id"=>2})
screen.instance_variable_set(:@action_clock,clocks.first)
assert(screen.send(:action_context).now == 141, "real screen bypassed logical clock")
puts "PASS clocks: 20 skew/limit cases, Scrabble/Taboo causal encoding, strict stale validation, +/-6h clients, outage, pause and restore"
