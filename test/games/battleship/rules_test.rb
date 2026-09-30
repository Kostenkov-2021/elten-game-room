require_relative "../../support/new_games_fixture"
require_relative "../../../lib/hidden_submissions"

game = GameRoomGames::Battleship.new
players = %w[Alice Bob]

def battleship_context(vault)
  GameRoomGames::ActionContext.new(
    session_id: 7, hidden_submissions: vault,
    random_source: NewGames116Random.new, now: 1_800_000_000
  )
end

def same_player?(first, second)
  first.to_s == second.to_s
end

def blank(game, players, options = {})
  game.send(:initial_state, players, game.normalize_options(options))
end

def play_battleship(game, players, options = {})
  vault = HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new)
  context = battleship_context(vault)
  repository = NewGames116Repository.new(players)
  session = { "options" => JSON.generate(game.normalize_options(options)) }
  events = []
  replay = game.replay(session, events, repository)
  strategy = game.bot_strategy
  random = NewGames116Random.new
  guard = 0
  while !replay.finished?
    guard += 1
    raise "Battleship did not finish" if guard > 5_000

    actor = game.active_actors(replay).first
    raise "no actor in #{replay.state[:phase]}" if actor == nil

    choice = game.automatic_action(replay, actor, context: context)
    if choice == nil && replay.state[:phase] == :placing
      choice = {
        "kind" => "grid", "action" => "seal",
        "ships" => JSON.generate(game.send(:random_fleet, replay.state))
      }
    end
    if choice == nil
      actions = game.legal_actions(replay, actor, context: context)
      raise "no legal actions in #{replay.state[:phase]}" if actions.empty?

      choice = strategy.choose(actions: actions, actor: actor, random_source: random, game: game, replay: replay)
    end
    replay = append_action(game, session, repository, events, replay, actor, choice, context)
  end
  [replay, events, session, repository, vault]
end

assert(game.id == "battleship", "Battleship has the wrong id")
assert(game.minimum_players == 2 && game.maximum_players == 2, "Battleship is not a two player game")
assert(!game.perfect_information?, "Battleship must hide the fleets")
assert(game.default_options["fleet"] == "polish", "the Polish fleet is not the default")
assert(!game.default_options.key?("placement"), "the removed placing option is still offered")
assert(!game.default_options.key?("extra_turn"), "the removed extra shot option is still offered")

state = blank(game, players)
assert(state[:fleet].sum == 20, "the Polish fleet does not cover twenty squares")
assert(blank(game, players, "fleet" => "classic")[:fleet].sum == 17, "the classic fleet does not cover seventeen squares")

fleet = game.send(:random_fleet, state)
assert(game.legal_fleet?(state, fleet), "a randomly placed fleet is not legal")
assert(fleet.flatten.uniq.length == 20, "a randomly placed fleet overlaps itself")
assert(fleet.map(&:length).sort == state[:fleet].sort, "a randomly placed fleet has the wrong ships")
20.times { assert(game.legal_fleet?(state, game.send(:random_fleet, state)), "random placing produced an illegal fleet") }

assert(!game.legal_fleet?(state, [[0, 1, 2, 3], [0, 1, 2], [10, 11, 12], [20, 21], [30, 31], [40, 41], [50], [60], [70], [80]]),
  "overlapping ships were accepted")
touching = [[0, 1, 2, 3], [10, 11, 12], [30, 31, 32], [50, 51], [70, 71], [90, 91], [5], [7], [9], [25]]
assert(!game.legal_fleet?(state, touching), "ships sharing a side were accepted")
assert(game.legal_fleet?(blank(game, players, "touching" => true), touching), "touching ships were refused when allowed")
assert(!game.legal_fleet?(state, [[0, 1, 11]] + Array.new(9) { |i| [40 + i * 2] }), "a bent ship was accepted")

replay, events, session, repository, vault = play_battleship(game, players)
final = replay.state
assert(replay.finished?, "the game did not finish")
assert(final[:winner] != nil, "the game has no winner")
assert(final[:invalid].empty?, "an honest game was reported as cheating")
assert(final[:fleets].keys.sort == players.sort, "both fleets were not opened")
assert(final[:commitments].keys.sort == players.sort, "both fleets were not sealed")
loser = players.find { |player| player != final[:winner] }
assert(final[:shots][final[:winner]].count { |_cell, result| result != "miss" } == final[:fleet].sum,
  "the winner did not sink every square")
assert(final[:shots][final[:winner]].count { |_cell, result| result == "sunk" } == final[:fleet].length,
  "the sinking of every ship was not reported")
assert(final[:shots][loser].length < 100, "the loser fired at every square")
assert(replay.history.any? { |entry| entry.kind == :verified }, "the final check was not recorded")

again = game.replay(session, events, repository)
assert(again.winner == replay.winner && again.state[:invalid].empty?, "the replay is not deterministic")

assert(events.none? { |event| event["action"] == "ship" }, "random placing published progress events")
seal = events.select { |event| event["action"] == "place" }
assert(seal.length == 2, "the fleets were not sealed once each")
assert(seal.all? { |event| /\A[0-9a-f]{64}\z/.match?(event["value"]) }, "a seal is not a digest")
assert(events.none? { |event| event["action"] == "place" && event["value"].include?(",") }, "a seal carries readable data")
opened = events.select { |event| event["action"] == "fleet" }
assert(opened.length == 2, "the fleets were not opened once each")
assert(events.index { |event| event["action"] == "fleet" } > events.index { |event| event["action"] == "shoot" },
  "a fleet was opened before the shooting began")

checked = blank(game, players)
sample = [[0, 1, 2, 3], [20, 21, 22], [40, 41, 42], [60, 61], [80, 81], [85, 86], [8], [28], [48], [68]]
assert(game.legal_fleet?(checked, sample), "the sample fleet is not legal")
digest, nonce, = HiddenSubmissions::Commitment.create({ "ships" => sample })
checked[:commitments]["Alice"] = digest
checked[:nonces]["Alice"] = nonce
checked[:fleets]["Alice"] = sample
checked[:order] = [["Bob", 0, "hit"], ["Bob", 5, "miss"]]
assert(game.send(:honest?, checked, "Alice"), "an honest fleet failed the final check")
checked[:order] = [["Bob", 0, "miss"]]
assert(!game.send(:honest?, checked, "Alice"), "a ship square called a miss passed the final check")
checked[:order] = [["Bob", 5, "hit"]]
assert(!game.send(:honest?, checked, "Alice"), "an empty square called a hit passed the final check")
checked[:order] = [["Bob", 8, "hit"]]
assert(!game.send(:honest?, checked, "Alice"), "a one mast ship sunk in one shot was only called a hit")
checked[:order] = [["Bob", 8, "sunk"]]
assert(game.send(:honest?, checked, "Alice"), "a correctly reported sinking failed the final check")
checked[:order] = [["Bob", 0, "sunk"]]
assert(!game.send(:honest?, checked, "Alice"), "a ship called sunk on its first square passed the final check")
checked[:order] = [["Bob", 0, "hit"], ["Bob", 1, "hit"], ["Bob", 2, "hit"], ["Bob", 3, "hit"]]
assert(!game.send(:honest?, checked, "Alice"), "the last square of a ship was not reported as a sinking")
checked[:order] = [["Bob", 0, "hit"], ["Bob", 1, "hit"], ["Bob", 2, "hit"], ["Bob", 3, "sunk"]]
assert(game.send(:honest?, checked, "Alice"), "a four mast ship sunk square by square failed the final check")
checked[:order] = []
checked[:fleets]["Alice"] = sample.map { |cells| cells.map { |cell| (cell + 1) % 100 } }
assert(!game.send(:honest?, checked, "Alice"), "a fleet that does not match its seal passed the final check")

liar_session = { "options" => JSON.generate(game.normalize_options({})) }
liar_events = [
  { "id" => 1, "actor" => "Alice", "action" => "place", "value" => "a" * 64 },
  { "id" => 2, "actor" => "Bob", "action" => "place", "value" => "b" * 64 }
]
identifier = 3
100.times do |cell|
  [["Alice", "Bob"], ["Bob", "Alice"]].each do |shooter, target|
    liar_events << { "id" => identifier, "actor" => shooter, "action" => "shoot", "value" => cell.to_s }
    liar_events << { "id" => identifier + 1, "actor" => target, "action" => "answer", "value" => "miss" }
    identifier += 2
  end
end
stalled = game.replay(liar_session, liar_events, repository)
assert(stalled.state[:phase] == :revealing, "endless denial never reached the final check")
assert(stalled.state[:shots]["Alice"].length <= 81, "the check waited for the whole board to be shot")

forged = events.map(&:dup)
fleet_event = forged.find { |event| event["action"] == "fleet" }
fleet_event["value"] = JSON.generate([[0, 1, 2, 3], [20, 21, 22], [40, 41, 42], [60, 61], [80, 81], [85, 86], [8], [28], [48], [68]])
swapped = game.replay(session, forged, repository)
assert(!swapped.state[:invalid].empty?, "a fleet that does not match its seal passed the final check")
assert(swapped.winner != nil && swapped.winner != swapped.state[:invalid].first, "the cheating player was not punished")

vault = HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new)
context = battleship_context(vault)
repository = NewGames116Repository.new(players)
session = { "options" => JSON.generate(game.normalize_options({})) }
events = []
replay = game.replay(session, events, repository)
assert(game.active_actors(replay).sort == players.sort, "both players do not place at the same time")
board = game.surface_spec(replay, "Alice")
assert(board.is_a?(GameSurfaces::FleetGridSpec), "hand placing does not use the fleet board")
assert(game.legal_actions(replay, "Alice", context: context).empty?,
  "hand placing asks the game for actions it handles on the board")

assert(board.place.call([], 0, 11).first == nil, "a diagonal ship was accepted")
assert(board.place.call([], 90, 94).first == nil, "a five mast ship was accepted into the Polish fleet")
assert(board.place.call([], 0, 3) == [[0, 1, 2, 3], nil], "a legal four mast ship was refused")
assert(board.place.call([[0, 1, 2, 3]], 10, 12).first == nil, "a ship touching another was accepted")
assert(!board.complete.call([[0, 1, 2, 3]]), "an unfinished fleet counts as complete")
assert(board.complete.call(sample), "a finished fleet does not count as complete")
assert(board.status.call([]).include?("4"), "the board does not say which ships are left")
assert(board.placed_message.call([0, 1, 2, 3], []).to_s != "", "placing a ship says nothing")

laid = []
sample.each do |ship|
  cells, refusal = board.place.call(laid, ship.first, ship.last)
  assert(cells != nil, "the fleet cannot be laid out by hand: #{refusal}")
  laid << cells
end
assert(board.complete.call(laid), "the whole fleet cannot be placed by hand")
assert(laid.count { |cells| cells.length == 1 } == 4, "the one mast ships were not placed")
assert(board.place.call([], 55, 55) == [[55], nil], "a one mast ship cannot be marked on a single square")
assert(board.place.call(laid, 55, 55).first == nil, "a ship was placed beyond the fleet")

status, = game.action_for({ "kind" => "command", "action" => "seal" }, replay, "Alice", context: context)
assert(status == :not_ready, "an unfinished fleet was sealed by hand")
replay = append_action(game, session, repository, events, replay, "Alice",
  { "kind" => "grid", "action" => "seal", "ships" => JSON.generate(sample) }, context)
assert(events.count { |event| event["action"] == "place" } == 1, "sealing a hand placed fleet took more than one event")
assert(events.none? { |event| event["action"] == "ship" }, "hand placing still sends an event for each ship")
assert(replay.state[:commitments].key?("Alice"), "the hand placed fleet was not sealed")
assert(replay.state[:phase] == :placing, "the game started before both fleets were sealed")

state = blank(game, players)
state[:shots]["Alice"] = { 44 => "hit", 45 => "miss" }
assert(game.send(:result_label, "sunk") != game.send(:result_label, "hit"), "a sinking reads the same as a hit")
assert(game.send(:answer_text, 0, "sunk") != game.send(:answer_text, 0, "hit"), "a sinking is announced as a plain hit")
values = (0...100).map { |cell| [cell, game.bot_action_score(
  GameRoomGames::Replay.new(players: players, current_player: "Alice", winner: nil, draw: false,
    state: state.merge(phase: :playing, current_player: "Alice"), accepted_events: [], history: []),
  "Alice", { "action" => "select", "x" => cell % 10, "y" => cell / 10 }
)] }.to_h
assert(values[34] > values[0] && values[54] > values[0] && values[43] > values[0],
  "the bot does not chase a wounded ship")
assert(values[44] < 0 && values[45] < 0, "the bot shoots at a square it already tried")

vault = HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new)
context = battleship_context(vault)
repository = NewGames116Repository.new(players)
session = { "options" => JSON.generate(game.normalize_options({})) }
replay = game.replay(session, [], repository)
opening = game.automatic_action(replay, "Alice", context: context)
assert(opening != nil && opening["action"] == "begin", "the game does not open with an event of its own")
surface = game.surface_spec(replay, "Alice")
assert(surface.is_a?(GameSurfaces::FleetGridSpec), "the game does not open on the fleet board")
assert(surface.cells.length == 10 && surface.cells.first.length == 10, "the board has the wrong size")
undo = game.game_shortcuts(replay, "Alice").find { |shortcut| shortcut.key == "backspace" }
assert(undo != nil && undo.kind == :surface, "Backspace does not reach the board")
assert(undo.action_name == "undo", "Backspace sends the wrong command")
assert(game.legal_actions(replay, "Alice", context: context).empty?, "a person is offered an automatic placing action")
bot_repository = NewGames116Repository.new(["Alice", "bot:1:1"])
bot_replay = game.replay(session, [], bot_repository)
assert(game.legal_actions(bot_replay, "bot:1:1", context: context).length == 1, "a participating computer cannot place its fleet")
assert(game.legal_actions(replay, "bot:1:1", context: context).empty?, "a nonparticipant can place a fleet")

def battleship_identity(spec)
  return "#{spec.class.name}:#{spec.respond_to?(:id) ? spec.id : ''}" if !spec.is_a?(GameSurfaces::CompositeSpec)

  parts = spec.parts.to_a.map { |part| "#{part.id}=#{battleship_identity(part.surface)}" }
  "#{spec.class.name}[#{parts.join('|')}]"
end

vault = HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new)
context = battleship_context(vault)
repository = NewGames116Repository.new(players)
session = { "options" => JSON.generate(game.normalize_options({})) }
sealed = [
  { "id" => 1, "actor" => "Alice", "action" => "start", "value" => "" },
  { "id" => 2, "actor" => "Alice", "action" => "place", "value" => "a" * 64 },
  { "id" => 3, "actor" => "Bob", "action" => "place", "value" => "b" * 64 }
]
mine = game.replay(session, sealed, repository)
assert(mine.state[:phase] == :playing, "the game did not start once both fleets were sealed")

layout = game.surface_spec(mine, "Alice")
assert(layout.is_a?(GameSurfaces::CompositeSpec), "the game does not show two boards")
assert(layout.parts.map(&:id) == %w[enemy own], "the two boards are not the enemy waters and your own")
assert(layout.parts.all? { |part| part.surface.is_a?(GameSurfaces::GridSpec) }, "a board is not a grid")
assert(layout.parts.all? { |part| part.surface.cells.length == 10 }, "a board has the wrong size")
assert(layout.parts.map { |part| part.surface.header.to_s }.none?(&:empty?), "a board does not name itself")
assert(layout.parts.first.surface.header.include?("Enter"), "the enemy board does not say how to shoot")

theirs = game.surface_spec(mine, "Bob")
assert(theirs.is_a?(GameSurfaces::CompositeSpec), "the waiting player loses the boards")
assert(battleship_identity(layout) == battleship_identity(theirs),
  "the boards change identity between turns, which resets the cursor")

after_shot = game.replay(session, sealed + [
  { "id" => 4, "actor" => "Alice", "action" => "shoot", "value" => "0" },
  { "id" => 5, "actor" => "Bob", "action" => "answer", "value" => "miss" }
], repository)
assert(battleship_identity(game.surface_spec(after_shot, "Alice")) == battleship_identity(layout),
  "the boards change identity after a shot, which resets the cursor")
assert(after_shot.current_player == "Bob", "the turn did not pass after a miss")
assert(game.surface_spec(after_shot, "Alice").parts.first.surface.cells.flatten.count { |cell| cell.include?("miss") } == 1,
  "a miss is not marked on the enemy board")
assert(game.surface_spec(after_shot, "Bob").parts.last.surface.cells.flatten.count { |cell| cell.include?("miss") } == 1,
  "a shot at you is not marked on your own board")

placing = game.replay({ "options" => JSON.generate(game.normalize_options({})) }, [], repository)
board = game.surface_spec(placing, "Alice")
assert(board.confirm_message.to_s != "", "the fleet is sealed without asking")
assert(board.bow_check != nil, "the board does not check the bow square")
assert(board.bow_check.call([], 0) == nil, "an empty board refused a bow")

crowded = sample[1..]
assert(game.send(:remaining_sizes, placing.state, crowded) == [4], "the sample leaves something other than the four mast ship")
assert(board.bow_check.call(crowded, 3) == nil, "a square with room for the last ship was refused")
assert(board.bow_check.call(crowded, 30).to_s.include?("A4"), "a square with no room for any ship was accepted")
assert(board.bow_check.call(sample, 30) != nil, "a bow was accepted with the fleet already complete")

ordered = [
  { "id" => 1, "actor" => "Alice", "action" => "start", "value" => "" },
  { "id" => 2, "actor" => "Alice", "action" => "place", "value" => "a" * 64 },
  { "id" => 3, "actor" => "Bob", "action" => "place", "value" => "b" * 64 }
]
opening = game.replay(session, ordered, repository)
shot = game.replay(session, ordered + [{ "id" => 4, "actor" => "Alice", "action" => "shoot", "value" => "5" }], repository)
assert(game.turn_transition_history_entry(opening, shot, event_id: 4) == nil,
  "shooting announces the turn before the answer is known")
assert(same_player?(shot.current_player, "Alice"), "shooting handed the turn over before the answer")
assert(game.active_actors(shot) == ["Bob"], "the shot is not answered by its target")

answered = game.replay(session, ordered + [
  { "id" => 4, "actor" => "Alice", "action" => "shoot", "value" => "5" },
  { "id" => 5, "actor" => "Bob", "action" => "answer", "value" => "miss" }
], repository)
assert(game.describe_event({ "id" => 5 }, repository, answered, "Alice").to_a.join.include?("miss"),
  "the answer is not announced")
assert(game.turn_transition_history_entry(shot, answered, event_id: 5).to_s != "",
  "the turn is not announced after the answer")
assert(same_player?(answered.current_player, "Bob"), "the turn did not pass after the answer")

locker = HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new)
first = locker.prepare(session_id: 1, round_id: "fleet", user: "Alice", payload: { "ships" => sample })
second = locker.prepare(session_id: 1, round_id: "fleet", user: "Bob", payload: { "ships" => sample })
third = locker.prepare(session_id: 2, round_id: "fleet", user: "Alice", payload: { "ships" => sample })
assert([first, second, third].all? { |envelope| /\A[0-9a-f]{64}\z/.match?(envelope.nonce) },
  "a seal is made without a full length random nonce")
assert([first, second, third].map(&:nonce).uniq.length == 3, "two seals reused the same nonce")
assert([first, second, third].map(&:commitment).uniq.length == 3,
  "the same fleet always seals to the same digest, so a dictionary would break it")
assert(HiddenSubmissions::Commitment.create({ "ships" => sample }).first !=
  HiddenSubmissions::Commitment.create({ "ships" => sample }).first,
  "sealing a fleet twice gives the same digest")

sunk_shots = { 0 => "hit", 1 => "sunk", 40 => "hit" }
model_state = blank(game, players).merge(shots: { "Alice" => sunk_shots })
assert(game.bot_strategy.cell_value(game, model_state, "Alice", 2) < 0, "the computer keeps shooting around a ship it already sank")
assert(game.bot_strategy.cell_value(game, model_state, "Alice", 41) > 0, "the computer stopped chasing a ship that is still afloat")

puts "Battleship model tests passed"
