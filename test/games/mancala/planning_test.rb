require_relative "../../support/new_games_fixture"
require_relative "../../../lib/game_simulation"
require_relative "../../../lib/game_sounds"
require_relative "../../../lib/saved_games"

game = GameRoomGames::Mancala.new
players = %w[Alice Bob]
repo = NewGames116Repository.new(players)
blank = ->(variant) { game.send(:initial_state, players, game.normalize_options("variant" => variant)) }
wrap = ->(state, history = []) { game.wrap(players, state, [], history) }
state = blank.call("ayoayo")
state[:pits] = [1,0,4,0,0,0,19,0,2,0,0,3,0,19]
assert(game.send(:apply_sow, state, { "id" => 1, "value" => "0" }, "Alice", repo, []), "Ayoayo capture refused")
assert(state[:pits][6] == 23 && state[:pits][1] == 0 && state[:pits][11] == 0, "Ayoayo lost the approved own-seed capture")
state = blank.call("ayoayo")
state[:pits] = [3,0,0,0,0,0,22,0,0,0,0,0,0,23]
game.send(:settle, state, 1, [])
assert(state[:pits].values_at(6, 13) == [22,26] && state[:winner] == "Bob", "Ayoayo remainder no longer belongs to the last mover")
state = blank.call("ayoayo")
state[:pits] = [0,0,0,0,0,0,22,3,0,0,0,0,0,23]
game.send(:settle, state, 1, [])
assert(state[:pits].values_at(6, 13) == [22,26], "empty next row gave remaining seeds to wrong player")

low = blank.call("oware")
low[:pits] = [1,0,0,0,0,0,23,1,0,0,0,0,0,23]
high = low.merge(pits: low[:pits].dup, idle: 119)
assert(game.bot_search_key(wrap.call(low), "Alice") != game.bot_search_key(wrap.call(high), "Alice"), "idle counts collide")
[low, high].each { |s| game.send(:apply_sow, s, { "id" => 1, "value" => "0" }, "Alice", repo, []) }
assert([low[:phase], high[:phase]] == [:playing, :finished], "idle test does not exercise different continuations")

state = blank.call("oware")
state[:current_player] = "Bob"
history = []
event = { "id" => 1, "actor" => "Bob", "action" => "sow", "value" => "0" }
before = wrap.call(Marshal.load(Marshal.dump(state)))
game.send(:apply_sow, state, event, "Bob", repo, history)
replay = wrap.call(state, history)
assert(game.describe_event(event, repo, replay, "Alice").join.include?("F2"), "Alice hears the wrong pit")
assert(game.describe_event(event, repo, replay, "Bob").join.include?("A1"), "Bob hears the wrong pit")
assert(game.history_entries_for_display(replay, "Observer").first.text.include?("F2"), "observer history differs from displayed board")
assert(history.first.text.include?("A1"), "display mapping mutated canonical history")
state[:pits][6], state[:pits][13] = 2, 10
assert(game.shortcut_feature_data(:scores, replay, "Alice")[:message].index("Bob") < game.shortcut_feature_data(:scores, replay, "Alice")[:message].index("Alice"), "S does not sort scores")
assert(Array(GameRoomSounds.event_cue(game: game, event: event, before_replay: before, after_replay: replay, repository: repo, viewer: "Alice")).include?("domino_move_tile"), "missing sow sound")

%w[oware ayoayo kalah].each do |variant|
  %w[calm steady sharp].each do |skill|
    instance = GameRoomGames::Mancala.new
    env = GameRoomSimulation::Environment.new_game(game: instance, players: players, options: { "variant" => variant, "skill" => skill })
    original = Marshal.dump(env.replay.state)
    choice = instance.bot_strategy.choose(actions: env.legal_actions, actor: env.active_actor,
      random_source: env.random_source, game: instance, replay: env.replay, context: env.context, simulation: env)
    stats = instance.strategy_for(skill).last_stats
    assert(env.legal_actions.include?(choice), "#{variant}/#{skill} chose an illegal action")
    assert(stats[:nodes].to_i > 0 && stats[:completed_depth].to_i > 0, "#{variant}/#{skill} silently fell back without planning")
    assert(stats[:nodes] <= instance.class::LEVELS.fetch(skill)[:nodes], "planner exceeded node budget")
    assert(Marshal.dump(env.replay.state) == original, "search changed the live position")
    puts "#{variant}/#{skill}: #{stats[:nodes]} nodes, depth #{stats[:completed_depth]}"
  end
end

# Saving/waking Mancala uses only canonical events, including repeat turns.
memory = Object.new
memory.define_singleton_method(:read_json) { |path, default:| (@files ||= {}).fetch(path, default) }
memory.define_singleton_method(:update_json) do |path, default:, &block|
  value = (@files ||= {}).fetch(path, default)
  block.call(value)
  @files[path] = value
end
%w[oware ayoayo kalah].each do |variant|
  env = GameRoomSimulation::Environment.new_game(game: game, players: players, options: { "variant" => variant })
  8.times do
    break if env.finished?
    env.step(env.legal_actions.first)
  end
  next if env.finished?
  saves = SavedGames.new(memory, owner: "Alice")
  snapshot = Struct.new(:session, :events).new(env.session, env.events)
  row = saves.put(game: game, table: { "owner" => "Alice", "name" => "Test" }, snapshot: snapshot, repository: env.repository)
  restored = saves.restored_data(row, game: game, table_id: 12)
  resumed = game.replay(env.session, restored[:events], repo)
  assert(resumed.state == env.replay.state, "#{variant} changed on archive replay")
end
puts "PASS Mancala: approved Ayoayo variant, viewer coordinates, score order, actual nine planners and archive replay"
