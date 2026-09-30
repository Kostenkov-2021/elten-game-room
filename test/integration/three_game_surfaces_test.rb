require_relative "../support/new_games_fixture"
require_relative "../support/log"
require_relative "../../games/rummy"
require_relative "../../games/domino"
require_relative "../../games/mexican_train"
require_relative "../../lib/game_repository"
require_relative "../../lib/saved_games"

module Session
  def self.name; "Alice"; end
end

class IntegrationStorage
  def initialize; @data = {}; end
  def read_json(_path, default:); JSON.parse(JSON.generate(@data)); end
  def update_json(_path, default:); yield @data; end
end

class CountedGameTransport
  attr_reader :calls
  def initialize; @calls = []; end
  def live_store?; true; end
  def append_game_action(**args); @calls << args; []; end
end

def round_inventory(game, state)
  items = state[:hands].values.flatten + state[:stock]
  case game.id
  when "rummy" then items + state[:discard] + state[:melds].flat_map { |m| m[:cards] }
  when "domino" then items + state[:chain].map { |t| t[:tile] }
  when "mexican_train"
    items + state[:trains].values.flat_map { |t| t[:chain].map { |v| v[:tile] } } + [GameRoomDominoTiles.tile(state[:station], state[:station])]
  end
end

def check_archive(game, replay, session, events, repository)
  return false if game.save_game_error(replay)
  events.each_with_index { |e, i| e.merge!("sequence" => i, "created_at" => 1_800_000_000) }
  saves = SavedGames.new(IntegrationStorage.new, owner: "Alice")
  snapshot = Struct.new(:session, :events).new(session, events)
  row = saves.put(game: game, table: { "owner" => "Alice", "name" => game.name }, snapshot: snapshot, repository: repository, now: 1_800_000_020)
  restored = saves.restored_data(row, game: game, table_id: 99, now: 1_800_001_000)
  new_session = session.merge("__players" => restored[:players], "__clock_offset" => restored[:clock_offset])
  after = game.replay(new_session, restored[:events], SavedGames::ReplayRepository.new)
  mapping = session["__players"].zip(restored[:players]).to_h
  replay.state[:hands].each { |p, cards| assert(after.state[:hands][mapping[p]] == cards, "#{game.id} restored physical cards") }
  %i[phase round turn drawn pending series station turn_deadline].each do |key|
    assert(after.state[key] == replay.state[key], "#{game.id} archive lost #{key}")
  end
  assert(after.current_player == mapping[replay.current_player], "#{game.id} restored turn owner")
  assert(after.accepted_events.size == events.size, "#{game.id} rejected restored events")
  assert(1_800_001_000 - restored[:clock_offset] == row["game_time"], "#{game.id} clock changed while saved")
  true
end

# A handful of bounded traces, not hundreds of simulated matches. Every
# accepted move checks card/tile conservation; replay and archive are the
# actual application paths, including physical bot-seat remapping.
scenarios = [
  [GameRoomGames::Rummy.new, { "first_meld" => 15 }],
  [GameRoomGames::Rummy.new, { "first_meld" => 15, "identities" => true, "manipulation" => true, "elimination" => true, "discard_mode" => "multiple" }],
  [GameRoomGames::Domino.new, { "tile_set" => "d12", "draw_until" => true }],
  [GameRoomGames::Domino.new, { "tile_set" => "4d12", "teams" => true, "whole_team" => true }],
  [GameRoomGames::MexicanTrain.new, {}]
]
checked_pending = false
scenarios.each do |game, settings|
  players = ["Alice", "bot:17:1", "bot:17:2"]
  players << "Bob" if settings["teams"]
  repo = NewGames116Repository.new(players)
  session = { "options" => JSON.generate(game.normalize_options(settings)), "__players" => players }
  replay, events = game.replay(session, [], repo), []
  random = NewGames116Random.new
  archived = false
  initial_inventory = nil
  decision_ms = 0
  130.times do |index|
    break if replay.finished?
    context = context_for(random)
    action = game.automatic_action(replay, "Alice", context: context)
    actor = "Alice"
    unless action
      actor = replay.current_player
      before = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      choices = game.legal_actions(replay, actor, context: context)
      assert(!choices.empty?, "#{game.id} stuck without a legal or automatic action at #{index}")
      action = choices.max_by { |a| game.bot_action_score(replay, actor, a, context: context) }
      decision_ms = [decision_ms, (Process.clock_gettime(Process::CLOCK_MONOTONIC) - before) * 1000].max
    end
    old_round = replay.state[:round]
    old_count = replay.accepted_events.length
    replay = append_action(game, session, repo, events, replay, actor, action, context)
    assert(replay.accepted_events.length > old_count, "#{game.id} accepted action not replayed")
    inventory = round_inventory(game, replay.state).sort
    initial_inventory = inventory if replay.state[:round] != old_round
    assert(inventory == initial_inventory && inventory.uniq == inventory, "#{game.id} lost/duplicated physical items")
    need_pending = game.id == "mexican_train" && !replay.state[:pending].empty? && !checked_pending
    if (!archived && index >= 5) || need_pending
      saved = check_archive(game, replay, session, events, repo)
      archived ||= saved
      checked_pending ||= saved && need_pending
    end
    if index % 23 == 0
      duplicate = game.replay(session, events + events.last(1), repo)
      assert(duplicate.state == replay.state, "#{game.id} duplicate delivery mutated state")
    end
  end
  assert(archived, "#{game.id} did not check an active archive")
  assert(game.replay(session, events, repo).state == replay.state, "#{game.id} replay nondeterminism")
  puts "#{game.id} #{settings}: #{events.length} events, archive/physical IDs/replay OK, max decision #{decision_ms.round(1)} ms"
end
assert(checked_pending, "no archive covered unfinished doubles")

# Actual repository boundary: even 200+ draws are one short command in one
# transport call. Retrying that command in the same turn cannot draw twice.
game = GameRoomGames::Domino.new
s = game.initial_state(%w[Alice Bob], game.normalize_options("tile_set" => "4d12", "draw_until" => true))
s.merge!(phase: :playing, round: 1, turn: 1, turn_started: 100, current_player: "Alice",
  hands: { "Alice" => ["660"], "Bob" => ["550"] }, chain: [{ tile: "120", left: 1, right: 2 }])
s[:stock] = GameRoomDominoTiles.deck(12, 4).reject { |t| %w[660 550].include?(t) || GameRoomDominoTiles.fits?(t, 1) || GameRoomDominoTiles.fits?(t, 2) } + ["220"]
r = GameRoomGames::Replay.new(players: s[:players], state: s, current_player: "Alice")
status, plan = game.action_for({ "action" => "draw" }, r, "Alice", context: GameRoomGames::ActionContext.new(now: 100))
assert(status == :ok && plan.events.one?, "large draw command")
transport = CountedGameTransport.new
repository = GameRepository.new(Object.new, transport: transport, server_tables: Object.new)
session = { "__id" => 3, "table_id" => 17, "__players" => %w[Alice Bob], "player_one" => "Alice" }
repository.append_events(session: session, sequence: 1, events: plan.events)
assert(transport.calls.length == 1 && transport.calls.first[:events].length == 1, "draw sends per tile")
data = game.send(:decode, plan.events.first.value)
assert(game.send(:apply, s, data, "Alice", 1, []) == :ok && s[:hands]["Alice"].length > 200, "long draw not exercised")
before = Marshal.load(Marshal.dump(s))
assert(game.send(:apply, s, data, "Alice", 2, []) == :invalid && s == before, "repeated long draw mutated state")

# Rummy's largest selection is several bounded fragments but still a single
# atomic append call. No new networking path is introduced by the game.
groups = GameRoomRummyRules.deck(4).reject { |c| GameRoomRummyRules.joker?(c) }.group_by { |c| GameRoomRummyRules.face(c) }.values
data = { "action" => "meld", "groups" => groups, "round" => 1, "turn" => 1, "time" => 100 }
commands = GameRoomActionPayload.commands("rummy", data)
repository.append_events(session: session, sequence: 2, events: commands)
assert(transport.calls.length == 2 && commands.length > 1, "Rummy fragmented its network writes")
assert(commands.all? { |c| c.value.length <= 64 } && commands.length <= 50, "Rummy exceeds existing protocol")
puts "Repository write count: long Domino draw 1; largest Rummy meld 1 (#{commands.length} bounded fragments): OK"
