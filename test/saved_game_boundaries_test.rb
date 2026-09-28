require_relative "support/native_live_sessions"
require_relative "../lib/saved_games"
require_relative "../lib/game_simulation"
require_relative "../content/monopoly_boards"
require_relative "../games/uno"
require_relative "../games/monopoly"
require_relative "../games/categories"
require_relative "../games/quiz_party"
require_relative "../games/chess"
def n_(one, many, count); count == 1 ? one : many; end

broker = NativeLiveSessionsBroker.new
owner = GameRoomTransport.new(ProgramDouble.new(broker.endpoint("Alice")))
bob = GameRoomTransport.new(ProgramDouble.new(broker.endpoint("Bob")))
repo = GameRepository.new(ProgramDouble.new(broker.endpoint("Alice")), transport: owner, server_tables: {})
remote_repo = GameRepository.new(ProgramDouble.new(broker.endpoint("Bob")), transport: bob, server_tables: {})
$game_room_test_user = "Alice"
table = owner.create_room(name: "Boundaries", game: "uno", owner: "Alice", game_options: "{}")
selected = bob.discover_rooms.first
assert(bob.establish_membership(table_id: table["__id"], owner: "Alice", capacity: 8, user: "Bob", table: selected), "Bob cannot join")
session = repo.start_session(table: table, game: "uno", players: %w[Alice Bob], options: "{}")
early = repo.append_events(session: session, sequence: 1, events: [GameRoomGames::EventCommand.new(action: "test_early", value: "")], actor: "Alice")
view = broker.endpoint("Bob").sessions.first
boundary = owner.freeze_game(session)
assert(remote_repo.snapshot_for(session)[ :session ]["__frozen"], "remote freeze was not visible without an action event")
# A move already in flight can reach the server after the owner freezes.
view.stack_push({ "kind" => "game_action", "version" => 2, "actor" => "Bob", "data" => {
  "session_id" => session["__id"], "sequence" => 2, "controller" => false,
  "events" => [{ "action" => "test_late", "value" => "", "move_id" => "late-flight" }] } }, message_id: "late-flight-packet")
assert(repo.snapshot_for(session).events.map { |event| event["action"] } == ["test_early"], "post-freeze move entered saved boundary")
assert(remote_repo.snapshot_for(session).events.map { |event| event["action"] } == ["test_early"], "remote projection accepted post-freeze move")
begin
  repo.append_events(session: session, sequence: 2, events: [GameRoomGames::EventCommand.new(action: "blocked", value: "")], actor: "Alice")
  raise "frozen game accepted local move"
rescue GameRoomNetworkErrors::GamePaused => error
  assert(error.message == "The game is being saved", "unexpected freeze error")
end
owner.freeze_game(session, frozen: false)
assert(!remote_repo.snapshot_for(session).session["__frozen"], "remote failed to unfreeze")
repo.append_events(session: session, sequence: 2, events: [GameRoomGames::EventCommand.new(action: "test_after", value: "")], actor: "Alice")
assert(repo.snapshot_for(session).events.map { |event| event["action"] } == %w[test_early test_after], "unfreeze resurrected stale move")

uno = GameRoomGames::Uno.new
env = GameRoomSimulation::Environment.new_game(game: uno, players: %w[Alice Bob], options: { "thinking_time" => 30 }, seed: 4)
state = env.replay.state
state[:colour_choice_player] = "Alice"
state[:colour_choice_card] = "W0"
assert(uno.save_game_error(env.replay) != nil, "UNO saved before colour selection")
state[:colour_choice_player] = nil
state[:colour_choice_card] = nil
monopoly = GameRoomGames::Monopoly.new
mono_replay = GameRoomSimulation::Environment.new_game(game: monopoly, players: %w[Alice Bob]).replay
mono_replay.state[:phase] = :auction
assert(monopoly.save_game_error(mono_replay) != nil, "Monopoly saved during auction")
[GameRoomGames::Categories.new, GameRoomGames::QuizParty.new].each { |game| assert(game.save_game_error(env.replay) != nil, "unsupported hidden-response game can be saved") }

# Clocks use the archived game time rather than wall time during the break.
deal = { "id" => 200, "sequence" => 1, "actor" => "Alice", "action" => "deal", "value" => "1|0|0123456789abcdef0123456789abcdef|1030", "created_at" => 1000 }
options = JSON.generate(uno.normalize_options("thinking_time" => 30))
sample = 1_800_000_000
original_clock = GameRoomClock.method(:now)
GameRoomClock.define_singleton_method(:now) { sample }
begin
  clock_session = { "__players" => %w[Alice Bob], "options" => options, "__clock_offset" => sample - 1010 }
  clock_replay = uno.replay(clock_session, [deal], SavedGames::ReplayRepository.new)
  assert(clock_replay.accepted_events.length == 1, "timed deal fixture invalid")
  timed = uno.game_shortcuts(clock_replay, "Alice").find { |shortcut| shortcut.key == "t" }
  assert(timed.message.end_with?("20 seconds remain."), "offline pause consumed UNO thinking time: #{timed.message}")
  sample += 7
  timed = uno.game_shortcuts(clock_replay, "Alice").find { |shortcut| shortcut.key == "t" }
  assert(timed.message.end_with?("13 seconds remain."), "resumed UNO thinking time did not advance: #{timed.message}")
ensure
  GameRoomClock.define_singleton_method(:now, original_clock)
end

# Missing archive pieces are not exposed as an incomplete game to readers.
owner.deactivate_table(table_id: table["__id"])
table = owner.create_room(name: "Incomplete archive", game: "chess", owner: "Alice", game_options: "{}")
store = owner.instance_variable_get(:@live_store)
record = store.send(:append_record, table["__id"], "game_started", {
  "session_id" => 9, "game" => "chess", "players" => %w[Alice Bob], "options" => "{}", "created_at" => Time.now.to_i,
  "archive_id" => "missing", "archive_events" => 1, "event_id_base" => 100, "clock_offset" => 0 }, actor: "Alice")
assert(store.send(:game_session_from, record) == nil, "partial archive was published as a playable game")
puts "Save boundaries, stale in-flight moves, exclusions, paused clocks and incomplete archives: OK"
