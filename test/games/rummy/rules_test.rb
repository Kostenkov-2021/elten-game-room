require_relative "../../../lib/game_surfaces/specifications"
require_relative "../../support/new_games_fixture"
require_relative "../../../games/rummy"

game = GameRoomGames::Rummy.new
rules = GameRoomRummyRules
players = %w[Alice Bob]
repo = NewGames116Repository.new(players)
session = { "options" => JSON.generate(game.default_options) }
events = []
replay = game.replay(session, events, repo)
replay = append_action(game, session, repo, events, replay, "Alice", { "action" => "deal" }, context_for)
assert(replay.state[:hands].values.all? { |h| h.length == 14 }, "deal size")
assert(replay.state[:stock].length == 80, "108 cards in two decks")
assert(replay.accepted_events.length == events.length, "fragmented deal accepted atomically")
assert(events.all? { |e| e["value"].length <= 64 }, "wire size")
assert(game.replay(session, events[0...-1], repo).state[:phase] == :awaiting_deal, "partial action ignored")
assert(game.replay(session, events + events, repo).state == replay.state, "duplicate delivery ignored")
assert(game.rule_book.documents.length == 2, "rules documents")
assert(game.game_shortcuts(replay, "Alice").any? { |s| s.key == "delete" }, "Delete shortcut")
assert(game.surface_spec(replay, "Alice").is_a?(GameSurfaces::MeldHandSpec), "meld surface")
assert(game.normalize_options("elimination" => true)["score_limit"] == 500, "elimination default")
assert(game.normalize_options("elimination" => true, "score_limit" => 700)["score_limit"] == 700, "explicit limit")

assert(rules.validate(%w[AS0 2S0 3S0]), "low ace")
assert(rules.validate(%w[QS0 KS0 AS0]), "high ace")
assert(!rules.validate(%w[KS0 AS0 2S0]), "no wrapping")
assert(!rules.validate(%w[3S0 5S0 4S0]), "selection order preserved")
assert(rules.validate(%w[X00 3S0 4S0])[:joker_face] == "2S", "leading joker")
assert(rules.validate(%w[3S0 4S0 X00])[:joker_face] == "5S", "trailing joker")
assert(rules.points(rules.validate(%w[3S0 4S0 X00])) == 15, "rounded joker")
assert(!rules.validate(%w[X00 3S0 X10]), "one joker maximum")
assert(!rules.validate(%w[7S0 7S1 7S2]), "identities off")
identity = rules.validate(%w[7S0 7S1 X00], identities: true)
assert(rules.points(identity) == 45 && identity[:joker_face] == "7S", "identity values")
set = rules.validate(%w[7S0 7H0 X00])
assert(set[:joker_face] == nil, "unfixed set suit")
additions = rules.additions(set, "7D0")
assert(additions.one? && additions.first[:mode] == :extend, "third natural extends")
set4 = additions.first[:meld]
assert(rules.additions(set4, "7C0").first[:mode] == :recover, "fourth suit recovers")
assert(rules.additions(set4, "X10").empty?, "no loose joker extension")
assert(rules.removable(set4).empty?, "cannot make a fixed joker ambiguous")
assert(rules.hand_value("AS0") == 15 && rules.hand_value("AS0", rounded: false) == 11, "hand ace")
assert(rules.hand_value("X00") == 20, "hand joker")
assert(rules.points(rules.validate(%w[AS0 2S0 3S0]), rounded: false) == 6, "unrounded low ace")

def fixture(game, base, cards, options = {})
  state = game.send(:copy_state, base)
  state[:options] = game.normalize_options(state[:options].merge(options))
  state[:hands] = { "Alice" => cards.dup, "Bob" => %w[KS1 QH1] }
  state[:stock] = %w[4D2 5D2 6D2]
  state[:discard] = []
  state[:drawn] = true
  state[:first_meld] = {}
  state[:turn_initial_hand] = cards.dup
  state
end

def apply(game, state, action, **args)
  data = { "action" => action, "round" => state[:round], "turn" => state[:turn], "time" => 1_800_000_000 }
  data.merge!(args.transform_keys(&:to_s))
  history = []
  status = game.send(:apply, state, data, "Alice", 10, history)
  [status, history]
end

state = fixture(game, replay.state, %w[2S0 3S0 4S0 6H0 7H0 8H0 9C0])
assert(apply(game, state, "meld", groups: [%w[2S0 3S0 4S0]]).first == :first_meld_too_small, "threshold")
assert(state[:melds].empty?, "failed threshold has no mutation")
assert(apply(game, state, "meld", groups: [%w[2S0 3S0 4S0], %w[6H0 7H0 8H0]]).first == :ok, "combined first meld")
assert(state[:scores]["Alice"] == 30 && state[:hands]["Alice"] == ["9C0"], "combined score")
assert(state[:first_meld]["Alice"], "first done")

state = fixture(game, replay.state, %w[2S0 3S0 4S0 6H0 7H0 8H0])
apply(game, state, "meld", groups: [%w[2S0 3S0 4S0], %w[6H0 7H0 8H0]])
assert(state[:phase] == :round_complete && state[:scores]["Alice"] == 450, "pure rummy 30+300+100+20")
state = fixture(game, replay.state, %w[2S0 3S0 4S0 6H0 7H0 8H0], "elimination" => true)
apply(game, state, "meld", groups: [%w[2S0 3S0 4S0], %w[6H0 7H0 8H0]])
assert(state[:scores]["Alice"] == 0 && state[:scores]["Bob"] == 80, "quadruple elimination")

state = fixture(game, replay.state, %w[9C0], "manipulation" => true, "discard_mode" => "none")
state[:first_meld]["Alice"] = true
state[:melds] = [rules.validate(%w[2S0 3S0 4S0 5S0]).merge(id: 1)]
assert(apply(game, state, "take", target: 1, card: "2S0").first == :ok, "take end")
assert(state[:scores]["Alice"] == -5 && state[:debts] == ["2S"], "old value deducted and debt")
assert(apply(game, state, "end").first == :ok && state[:scores]["Alice"] == -305, "keep for 300")
assert(state[:debts].empty? && state[:hands]["Alice"].include?("2S0"), "debt paid once, card retained")

state = fixture(game, replay.state, %w[2S1 9C0], "manipulation" => true)
state[:first_meld]["Alice"] = true
state[:melds] = [rules.validate(%w[2S0 3S0 4S0 5S0]).merge(id: 1)]
apply(game, state, "take", target: 1, card: "2S0")
assert(apply(game, state, "add", card: "2S1", target: 1, mode: "extend").first == :ok, "equivalent copy can repay")
assert(state[:debts].empty? && state[:scores]["Alice"] == 0, "no point farming")

state = fixture(game, replay.state, %w[2S1 9C0], "manipulation" => true, "discard_mode" => "none")
state[:first_meld]["Alice"] = true
state[:melds] = [rules.validate(%w[X00 3S0 4S0]).merge(id: 1)]
assert(apply(game, state, "take", target: 1).first == :invalid, "cannot take joker meld")
assert(apply(game, state, "add", card: "2S1", target: 1, mode: "recover").first == :ok, "replace joker")
assert(state[:debts] == ["X"] && state[:hands]["Alice"].last == "X00", "recovered joker last, debt")
apply(game, state, "end")
assert(state[:scores]["Alice"] == -300, "unplayed joker costs 300")

state = fixture(game, replay.state, %w[9C0], "discard_mode" => "multiple")
state[:first_meld]["Alice"] = true
state[:discard] = %w[2S0 3S0 4S0]
state[:drawn] = false
assert(apply(game, state, "draw", depth: 3).first == :ok, "draw packet")
assert(state[:hands]["Alice"] == %w[9C0 4S0 3S0 2S0], "actual acquisition order")
assert(apply(game, state, "draw").first == :invalid, "only one draw")

state = fixture(game, replay.state, %w[9C0], "thinking_time" => 20, "elimination" => true)
state[:debts] = %w[X 2S]
state[:turn_deadline] = 1_800_000_000
assert(apply(game, state, "timeout").first == :ok, "timeout")
assert(state[:hands]["Alice"] == %w[9C0], "no second timeout draw")
assert(state[:scores]["Alice"] == 650 && state[:current_player] == "Bob", "stacked penalties and immediate advance")
state = fixture(game, replay.state, %w[9C0], "thinking_time" => 20)
state[:drawn] = false
state[:turn_deadline] = 1_800_000_000
apply(game, state, "timeout")
assert(state[:hands]["Alice"] == %w[9C0 4D2], "timeout draws once if needed")

plans = GameRoomRummyPlanner.plans(%w[5S0 6S0 7S0 7H0 8H0 9H0 7C0], minimum: 30)
assert(plans.first[:cards].length == 6 && plans.first[:groups].length == 2, "don't break two runs for three sevens")
assert(plans.first[:cards].uniq.length == plans.first[:cards].length, "disjoint planned cards")
assert(game.bot_observation(replay, "Alice")["hand"] == replay.state[:hands]["Alice"], "own hand visible")
assert(!game.bot_observation(replay, "Alice").key?("stock"), "no hidden stock")
puts "Rummy rules, replay, fragments, scoring, manipulation, timer, UI definitions and planner: OK"
