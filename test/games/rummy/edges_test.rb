require_relative "../../support/new_games_fixture"
require_relative "../../../games/rummy"
game = GameRoomGames::Rummy.new
rules = GameRoomRummyRules
repo = NewGames116Repository.new(%w[Alice Bob])
session = { "options" => JSON.generate(game.default_options) }
events = []
replay = game.replay(session, events, repo)
replay = append_action(game, session, repo, events, replay, "Alice", { "action" => "deal" }, context_for)

def apply_edge(game, state, action, actor: state[:current_player], **extra)
  data = { "action" => action, "round" => state[:round], "turn" => state[:turn], "time" => 1_800_000_000 }.merge(extra.transform_keys(&:to_s))
  history = []
  [game.send(:apply, state, data, actor, 77, history), history]
end

state = game.send(:copy_state, replay.state)
state[:hands] = { "Alice" => %w[2S0 3S0 4S0], "Bob" => %w[2H0] }
assert(apply_edge(game, state, "meld", groups: [%w[2S0 3S0 4S0]]).first == :invalid, "meld before draw")
state[:stock] = []
state[:options]["first_meld"] = 15
assert(apply_edge(game, state, "meld", groups: [%w[2S0 3S0 4S0]]).first == :ok, "no source permits meld")

state = game.send(:copy_state, replay.state)
state[:hands] = { "Alice" => %w[2S0], "Bob" => %w[2H0] }
state[:stock] = []
state[:discard] = []
state[:options]["discard_mode"] = "none"
state[:turn_initial_hand] = %w[2S0]
3.times do
  assert(apply_edge(game, state, "end").first == :ok, "blocked pass")
  assert(state[:phase] == :playing, "blocked too early")
end
apply_edge(game, state, "end")
assert(state[:phase] == :round_complete && state[:scores].values == [0, 0], "blocked scoring")

state = game.send(:copy_state, replay.state)
state[:stock] = []
state[:discard] = %w[2S0 3S0 4S0]
state[:hands]["Alice"] = []
apply_edge(game, state, "draw", depth: 0)
assert(state[:discard] == ["4S0"] && state[:stock].length == 1 && state[:hands]["Alice"].length == 1, "recycle except top")

state = game.send(:copy_state, replay.state)
state[:options].merge!("manipulation" => true, "discard_mode" => "none")
state[:drawn] = true
state[:first_meld]["Alice"] = true
state[:melds] = [rules.validate(%w[2S0 3S0 4S0]).merge(id: 1), rules.validate(%w[5S0 6S0 7S0]).merge(id: 2)]
old_score = state[:scores]["Alice"]
assert(apply_edge(game, state, "merge", target: 1, second: 2).first == :ok, "merge ordered runs")
assert(state[:melds].one? && state[:melds].first[:cards].length == 6 && state[:scores]["Alice"] == old_score, "merge adds no fake points")

state = game.send(:copy_state, replay.state)
state[:options].merge!("elimination" => true, "score_limit" => 5)
state[:hands] = { "Alice" => ["2S0"], "Bob" => ["2H0"] }
history = []
game.send(:finish_round, state, nil, 1, history)
assert(state[:phase] == :finished && state[:winners] == %w[Alice Bob], "joint lowest victory")
state = game.send(:copy_state, replay.state)
state[:options]["score_limit"] = 50
state[:scores] = { "Alice" => 60, "Bob" => 60 }
game.send(:finish_round, state, nil, 1, [])
assert(state[:phase] == :round_complete, "normal tied leaders must continue")

state = game.send(:copy_state, replay.state)
state[:options]["thinking_time"] = 20
state[:turn_deadline] = 1_800_000_000
assert(apply_edge(game, state, "draw", depth: 0).first == :invalid, "deadline accepted late draw")
assert(apply_edge(game, state, "timeout").first == :ok, "due timeout rejected")
assert(state[:current_player] == "Bob" && state[:scores]["Alice"] == -50, "late-turn settlement")

# Worst-sized selection is fragmented inside one ActionPlan, not one write
# per card. Validation rejects reordered, missing or corrupt fragments.
groups = rules.deck(4).reject { |c| rules.joker?(c) }.group_by { |c| rules.face(c) }.values
data = { "action" => "meld", "groups" => groups, "round" => 1, "turn" => 1, "time" => 1_800_000_000 }
commands = GameRoomActionPayload.commands("rummy", data)
assert(commands.length <= 50 && commands.all? { |c| c.value.length <= 64 }, "largest wire action")
wire = commands.each_with_index.map { |c, i| { "id" => i + 1, "actor" => "Alice", "action" => c.action, "value" => c.value } }
decoded = []
GameRoomActionPayload.each(wire, "rummy", repo, session) { |d, *_| decoded << d }
assert(decoded == [data], "largest payload round trip")
[wire.reverse, wire[0...-1], wire.map.with_index { |e, i| i == 1 ? e.merge("actor" => "Bob") : e }].each do |bad|
  decoded = []
  GameRoomActionPayload.each(bad, "rummy", repo, session) { |d, *_| decoded << d }
  assert(decoded.empty?, "partial/interleaved fragment applied")
end

durations = [14, 32, 70].map do |count|
  cards = rules.deck(4).shuffle(random: Random.new(count)).first(count)
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  plans = GameRoomRummyPlanner.plans(cards, identities: true)
  assert(plans.all? { |p| p[:cards].uniq.length == p[:cards].length }, "planner duplicates")
  [count, ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(1)]
end
puts "Rummy no-stock, block, recycling, merge, limits and large payload: OK; planner ms #{durations.inspect}"
