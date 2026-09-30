require_relative "../../support/domino"

game = GameRoomGames::Domino.new
tiles = GameRoomDominoTiles
GameRoomGames::Domino::SETS.each do |key, (max, copies, deal, limit)|
  deck = tiles.deck(max, copies)
  assert(deck.length == (max + 1) * (max + 2) / 2 * copies && deck.uniq == deck, "physical set #{key}")
  players = Array.new(limit) { |i| "P#{i}" }
  options = game.normalize_options("tile_set" => key)
  repo = NewGames116Repository.new(players)
  session = { "options" => JSON.generate(options) }
  events = []
  replay = game.replay(session, events, repo)
  replay = append_action(game, session, repo, events, replay, players.first, { "action" => "deal" }, context_for)
  assert(replay.state[:hands].values.all? { |h| h.length == deal }, "deal #{key}")
  assert(replay.state[:stock].length == deck.length - deal * limit, "stock #{key}")
  assert(events.one? && events[0]["value"].length <= 64, "one short deal #{key}")
  assert(game.replay(session, events + events, repo).state == replay.state, "repeated event #{key}")
  assert(game.validation_error(options, player_count: limit + 1), "capacity #{key}")
end


s = position(game, { "A" => %w[120 330], "B" => %w[450] })
assert(move(game, s, "play", tile: "120", target: "r").first == :ok, "arbitrary opening")
assert(s[:chain][0][:left] == 1 && s[:current_player] == "B", "opening/turn")
s = position(game, { "A" => %w[240 560], "B" => %w[220] }, chain: chain(2, 4))
assert(game.placements(s, "A").length == 2, "two legal ends")
assert(move(game, s, "play", tile: "240", target: "l").first == :ok, "left play")
assert(s[:chain].first.values_at(:left, :right) == [4, 2], "orientation")

s = position(game, { "A" => %w[660], "B" => %w[550] }, options: { "draw_until" => true, "tile_set" => "4d12" }, chain: chain(1, 2), stock: %w[330 440 340 450 220 560])
before = Marshal.load(Marshal.dump(s))
assert(move(game, s, "draw").first == :ok, "series")
assert(s[:hands]["A"] == %w[660 330 440 340 450 220] && s[:stock] == ["560"], "draw to first newly matching")
assert(move(game, s, "draw").first == :invalid, "second series prohibited")
status, plan = game.action_for({ "action" => "draw" }, replay_of(before), "A", context: GameRoomGames::ActionContext.new(now: 100))
assert(status == :ok && plan.events.one? && plan.events[0].value.length <= 64, "series one transport command")
assert(game.send(:decode, plan.events[0].value)["action"] == "draw", "compact packet decode")
assert(s[:current_player] == "A", "draw kept turn for playable tile")
s = position(game, { "A" => %w[110 660], "B" => %w[550] }, chain: chain(1, 2), stock: %w[340])
assert(move(game, s, "draw").first == :ok && s[:current_player] == "A", "old playable tile retained")
assert(!s[:voids].key?("A"), "voluntary draw not proof of void")
s[:options]["allow_playable_draw"] = false
s[:drawn] = false
s[:stock] = ["450"]
assert(move(game, s, "draw").first == :invalid, "drawing with playable forbidden")
o = game.normalize_options("forbid_draw" => true, "draw_until" => true, "allow_playable_draw" => true, "whole_team" => true)
assert(!o["draw_until"] && !o["allow_playable_draw"] && !o["whole_team"], "option dependencies")
assert(game.send(:hand_points, ["000"]) == 10 && game.send(:hand_points, %w[000 120]) == 3, "blank scoring")

s = position(game, { "A" => %w[330], "B" => %w[440] }, chain: chain(1, 2), stock: %w[120], options: { "forbid_draw" => true })
assert(move(game, s, "pass", actor: "A").first == :ok && s[:phase] == :playing, "first pass")
assert(move(game, s, "pass", actor: "A").first == :ok && s[:phase] == :round_complete, "full blocked orbit despite stock")
assert(s[:scores] == { "A" => 6, "B" => 8 }, "blocked points")

s = position(game, { "A" => %w[120], "B" => %w[220] }, chain: chain(1, 2), stock: %w[330], options: { "thinking_time" => 5 }, turn_deadline: 105)
assert(move(game, s, "play", time: 105, tile: "120", target: "r").first == :invalid, "deadline rejects late play")
assert(move(game, s, "timeout", time: 105).first == :ok && s[:hands]["A"] == %w[120 330] && s[:current_player] == "B", "timeout one draw")
s[:turn_deadline] = 106
assert(move(game, s, "timeout", actor: "A", time: 106).first == :ok && s[:phase] == :playing, "timeouts with legal moves not block")
s = position(game, { "A" => %w[120], "B" => %w[220] }, chain: chain(1, 2), stock: %w[330], options: { "thinking_time" => 5 }, turn_deadline: 105, drawn: true)
assert(move(game, s, "timeout", time: 105).first == :ok && s[:stock] == %w[330], "timeout after draw no second draw")

players = %w[A B C D E F]
options = game.with_team_assignment(game.normalize_options("teams" => true, "team_count" => "3", "tile_set" => "d12"), players: players, seats: [0, 0, 1, 1, 2, 2])
s = game.initial_state(players, options)
assert(s[:order] == %w[A C E B D F], "manual teams alternate")
s[:hands] = { "A" => [], "B" => ["440"], "C" => ["990"], "D" => ["110"], "E" => ["660"], "F" => ["120"] }
game.send(:finish_round, s, "A", 1, [])
assert(s[:scores] == { "team:0" => 0, "team:1" => 28, "team:2" => 23 }, "team penalty awarded to EACH loser")
s = position(game, { "A" => %w[120], "B" => %w[230], "C" => [], "D" => %w[330] }, options: { "teams" => true, "whole_team" => true }, chain: chain(1, 2))
assert(move(game, s, "play", tile: "120", target: "r").first == :ok && s[:phase] == :round_complete, "whole team finished")
s = position(game, { "A" => %w[120], "B" => %w[230], "C" => %w[330], "D" => %w[340] }, options: { "teams" => true, "whole_team" => true }, chain: chain(1, 2))
assert(move(game, s, "play", tile: "120", target: "r").first == :ok && s[:phase] == :playing, "one teammate not whole victory")
assert(!game.can_draw?(s.merge(current_player: "A", stock: %w[440])), "empty teammate cannot draw")

s = position(game, { "A" => %w[110], "B" => %w[220], "C" => %w[660] }, options: { "score_limit" => 10 })
s[:scores] = { "A" => 9, "B" => 7, "C" => 10 }
s[:eliminated] = { "C" => true }
game.send(:finish_round, s, nil, 1, [])
assert(s[:winners] == %w[A B], "tie among last survivors, not earlier eliminated")

s = position(game, { "A" => %w[120], "B" => %w[440] }, chain: chain(1, 2))
r = replay_of(s)
actions = game.legal_actions(r, "A")
assert(actions.all? { |a| game.bot_action_score(r, "A", a) >= 100_000 }, "bot takes immediate finish")
obs = game.bot_observation(r, "A")
s[:hands]["B"] = %w[550]
assert(obs == game.bot_observation(replay_of(s), "A"), "bot hidden-hand independence")
low = game.send(:bot_elimination_risk, s, "A", %w[660 550])
s[:scores]["A"] = 90
assert(game.send(:bot_elimination_risk, s, "A", %w[660 550]) > low, "bot ignored proximity to elimination")
s = position(game, { "A" => %w[121], "B" => %w[440], "C" => %w[130], "D" => %w[550] },
  options: { "tile_set" => "2d6", "teams" => true, "whole_team" => true }, chain: chain(1, 2), voids: { "C" => [2] })
r = replay_of(s)
best = game.legal_actions(r, "A").max_by { |a| game.bot_action_score(r, "A", a) }
assert(best["target"] == "r", "whole-team bot treats emptying itself as a win and blocks its partner")
scores = game.legal_actions(r, "A").map { |a| game.bot_action_score(r, "A", a) }
s[:hands]["C"] = %w[140]
assert(scores == game.legal_actions(r, "A").map { |a| game.bot_action_score(r, "A", a) }, "whole-team bot looked at its partner's tiles")
assert(game.rule_book.documents.length == 2, "rules and shortcuts")
puts "Domino sets, replay, drawing, deadlines, teams, scoring and bot checks: OK"
