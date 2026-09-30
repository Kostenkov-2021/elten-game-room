require_relative "../../support/domino"
require_relative "../../../games/mexican_train"
game = GameRoomGames::MexicanTrain.new
tiles = GameRoomDominoTiles
(2..8).each do |count|
  players = Array.new(count) { |i| "P#{i}" }
  repo = NewGames116Repository.new(players)
  session = { "options" => JSON.generate(game.default_options) }
  events = []
  r = game.replay(session, events, repo)
  r = append_action(game, session, repo, events, r, players.first, { "action" => "deal" }, context_for)
  hand_size = count <= 5 ? 15 : count <= 7 ? 12 : 10
  all = r.state[:hands].values.flatten + r.state[:stock]
  assert(r.state[:hands].values.all? { |h| h.length == hand_size }, "train deal #{count}")
  assert(all.uniq.length == 90 && !all.include?(tiles.tile(12, 12)), "station removed #{count}")
  assert(r.state[:stock].length == 90 - count * hand_size && r.state[:pending].empty?, "stock/station obligation #{count}")
  assert(game.replay(session, events + events, repo).state == r.state, "train repeated replay")
end
state = game.initial_state(%w[A B], game.default_options)
14.times do |index|
  state[:phase] = index == 0 ? :awaiting_deal : :round_complete
  assert(move(game, state, "deal", actor: "A", seed: "0" * 32).first == :ok, "deal cycle")
  assert(state[:station] == 12 - index % 13, "station cycle #{index}")
end

def trains(game, hands, ends: [6, 9, 9], **extra)
  state = position(game, hands, **extra)
  state[:trains] = {
    "p0" => { owner: hands.keys[0], end: ends[0], open: false, chain: [] },
    "p1" => { owner: hands.keys[1], end: ends[1], open: false, chain: [] },
    "m" => { owner: nil, end: ends[2], open: true, chain: [] }
  }
  state
end
s = trains(game, { "A" => %w[660 990 460 550], "B" => %w[790 260] })
assert(game.placements(s, "A").map { |a| a["target"] }.uniq.sort == %w[m p0], "closed other train inaccessible")
assert(!game.can_draw?(s.merge(stock: %w[120])), "default no voluntary draw")
assert(move(game, s, "play", tile: "660", target: "p0").first == :ok && s[:current_player] == "A" && s[:pending] == ["p0"], "double keeps turn")
assert(move(game, s, "play", tile: "990", target: "m").first == :ok && s[:pending] == %w[p0 m], "series on different train")
assert(move(game, s, "play", tile: "460", target: "p0").first == :ok && s[:pending] == ["m"] && s[:current_player] == "B", "older double covered, not blind pop")
assert(game.placements(s, "B").all? { |a| a["target"] == "m" && a["tile"] == "790" }, "next player forced latest")
assert(move(game, s, "play", tile: "260", target: "p0").first == :invalid, "cannot bypass pending double")
assert(move(game, s, "play", tile: "790", target: "m").first == :ok && s[:pending].empty?, "cover required double")
s = trains(game, { "A" => %w[460 550], "B" => %w[790 260] })
s[:trains]["m"][:end] = 5
s[:pending] = %w[p0 p1 m]
s[:series] = true
s[:trains]["p1"][:open] = true
s[:hands]["A"] << "490"
assert(move(game, s, "play", tile: "490", target: "p1").first == :ok && s[:pending] == %w[p0 m], "middle removal preserves remaining order")
assert(s[:trains]["p1"][:open], "other's train closed by foreign play")

s = trains(game, { "A" => %w[550 220], "B" => %w[790 260] }, stock: %w[660 120])
assert(game.placements(s, "A").empty?, "no tile matches any accessible train")
assert(move(game, s, "draw").first == :ok && s[:drawn], "draw a double")
assert(move(game, s, "draw").first == :invalid, "no second unresolved draw")
assert(move(game, s, "play", tile: "660", target: "p0").first == :ok && !s[:drawn], "double new decision resets draw")
assert(move(game, s, "draw").first == :ok && s[:current_player] == "B" && s[:trains]["p0"][:open], "bonus draw then opening/pass")

s = trains(game, { "A" => %w[460 550], "B" => %w[790] }, stock: %w[120], options: { "allow_playable_draw" => true })
assert(move(game, s, "draw").first == :ok && s[:current_player] == "A" && !s[:trains]["p0"][:open], "voluntary miss keeps legal old tile")
assert(!s[:voids].key?("A"), "voluntary draw doesn't imply void")
s[:trains]["p0"][:open] = true
assert(move(game, s, "play", tile: "460", target: "p0").first == :ok && !s[:trains]["p0"][:open], "own play closes train")

s = trains(game, { "A" => %w[660], "B" => %w[000 120] })
assert(move(game, s, "play", tile: "660", target: "p0").first == :ok && s[:phase] == :round_complete, "last double wins immediately")
assert(s[:scores] == { "A" => 0, "B" => 13 }, "blank always ten, with other tile")
assert(game.send(:hand_points, ["000"]) == 10, "sole blank ten")

# Both initially cannot play. Opening B's train enables A's 9, so no block.
s = trains(game, { "A" => %w[490], "B" => %w[220] }, ends: [6, 9, 6])
assert(move(game, s, "pass", actor: "A").first == :ok, "empty boneyard auto pass")
assert(move(game, s, "pass", actor: "A").first == :ok && s[:phase] == :playing, "newly opened train prevents false block")
assert(game.placements(s, "A").any? { |a| a["target"] == "p1" }, "opening made earlier player's move legal")
s = trains(game, { "A" => %w[110], "B" => %w[220] })
assert(move(game, s, "pass", actor: "A").first == :ok, "block pass one")
assert(move(game, s, "pass", actor: "A").first == :ok && s[:phase] == :round_complete, "true full orbit block")
assert(s[:scores] == { "A" => 2, "B" => 4 }, "block scoring")

s = trains(game, { "A" => %w[660 460], "B" => %w[790] })
r = replay_of(s)
best = game.legal_actions(r, "A").max_by { |a| game.bot_action_score(r, "A", a) }
assert(best["tile"] == "660", "bot missed double then finish")
obs = game.bot_observation(r, "A")
values = game.legal_actions(r, "A").map { |a| game.bot_action_score(r, "A", a) }
s[:stock] = s[:stock].reverse
s[:hands]["B"] = %w[550]
assert(obs == game.bot_observation(r, "A") && values == game.legal_actions(r, "A").map { |a| game.bot_action_score(r, "A", a) }, "train bot hidden information")
assert(game.rule_book.documents.length == 2, "train rules/shortcuts")
puts "Mexican Train deals, station cycle, trains, double stack, draw, block, score and bot checks: OK"
