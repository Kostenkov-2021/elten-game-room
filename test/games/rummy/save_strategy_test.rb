require_relative "../../support/new_games_fixture"
require_relative "../../../games/rummy"
require_relative "../../../lib/saved_games"

class RummySaveStorage
  def initialize; @data = {}; end
  def read_json(_path, default:); JSON.parse(JSON.generate(@data)); end
  def update_json(_path, default:); yield @data; end
end

game = GameRoomGames::Rummy.new
players = ["Alice", "Bob", "bot:12:1"]
repo = NewGames116Repository.new(players)
session = { "options" => JSON.generate(game.default_options), "__players" => players }
events = []
replay = game.replay(session, events, repo)
replay = append_action(game, session, repo, events, replay, "Alice", { "action" => "deal" }, context_for)
events.each_with_index { |e, i| e.merge!("sequence" => i + 1, "created_at" => 1_800_000_000) }
saves = SavedGames.new(RummySaveStorage.new, owner: "Alice")
snapshot = Struct.new(:session, :events).new(session, events)
row = saves.put(game: game, table: { "owner" => "Alice", "name" => "Rummy" }, snapshot: snapshot, repository: repo, now: 1_800_000_000)
restored = saves.restored_data(row, game: game, table_id: 99, now: 1_800_010_000)
after = game.replay(session.merge("__players" => restored[:players]), restored[:events], SavedGames::ReplayRepository.new)
assert(after.accepted_events.length == events.length, "restored fragments rejected")
assert(after.state[:hands]["bot:99:1"] == replay.state[:hands]["bot:12:1"], "bot seat remapping")
assert(game.save_game_error(after).nil?, "beginning-of-turn save")
drawn = append_action(game, session, repo, events, replay, "Alice", { "action" => "draw", "depth" => 0 }, context_for)
assert(game.save_game_error(drawn), "mid-turn save accepted")

base = game.send(:copy_state, drawn.state)
base[:options].merge!("manipulation" => true, "first_meld" => 15)
base[:first_meld]["Alice"] = true
base[:hands]["Alice"] = %w[2S0 3S0 9H0]
base[:melds] = [GameRoomRummyRules.validate(%w[4S0 4H0 4C0]).merge(id: 1)]
r = drawn.dup; r.state = base
actions = game.legal_actions(r, "Alice")
take = actions.find { |a| a["action"] == "take" }
assert(game.bot_action_score(r, "Alice", take) < -1000, "bot borrows unrecoverable group")
base[:hands]["Alice"] = %w[2S0 3S0 4S1 9H0]
assert(game.bot_action_score(r, "Alice", take) < -1000, "pointless borrowing over an available own meld")
base[:hands]["Alice"] = %w[2S0 3S0 5H0 6H0 5C0 6C0 9H0]
assert(game.bot_action_score(r, "Alice", take) > 0, "safe group rearrangement rejected")
base[:hands]["Alice"] = %w[5S0 9H0]
base[:melds] = [GameRoomRummyRules.validate(%w[2S0 3S0 4S0]).merge(id: 1)]
action = game.legal_actions(r, "Alice").max_by { |a| game.bot_action_score(r, "Alice", a) }
assert(action["action"] == "add" && action["card"] == "5S0", "missed free layoff")
base[:hands]["Alice"] = %w[2S0 3S0 4S0]
base[:melds] = []
action = game.legal_actions(r, "Alice").max_by { |a| game.bot_action_score(r, "Alice", a) }
assert(action["action"] == "meld", "missed round finish")
assert(game.option_editor_changes({ "elimination" => false }, { "elimination" => true, "score_limit" => 1000 }) == { "score_limit" => 500 }, "elimination default")
assert(game.option_editor_changes({ "elimination" => false }, { "elimination" => true, "score_limit" => 1500 }).empty?, "overwrote custom limit")
puts "Rummy archive, remapped bots, save boundary, defaults and tactical decisions: OK"
