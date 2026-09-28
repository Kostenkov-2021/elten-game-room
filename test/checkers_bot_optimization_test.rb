def _(text)
  text
end

require_relative "../lib/game_simulation"
require_relative "../games/checkers"

def assert(condition, message)
  raise message if !condition
end

# Reflect the recorded search fixtures onto the corrected board. The position
# and candidate move must be reflected together; production has one geometry.
def reflect_checkers_action(action, size)
  reflected = action.dup
  %w[from_x to_x].each { |key| reflected[key] = size - 1 - action.fetch(key) }
  if !action['capture'].to_s.empty?
    x, y = action['capture'].split(',').map(&:to_i)
    reflected['capture'] = "#{size - 1 - x},#{y}"
  end
  reflected
end

def deterministic_checkers_environment(name:, size:, plies:, salt:, seed:)
  game = GameRoomGames::Checkers.new
  environment = GameRoomSimulation::Environment.new_game(
    game: game,
    players: ["Computer 1", "Computer 2"],
    options: { "board_size" => size },
    seed: seed
  )
  plies.times do |index|
    break if environment.finished?

    actor = environment.active_actor
    actions = environment.legal_actions(actor).sort_by { |action| game.bot_action_key(reflect_checkers_action(action, size)) }
    raise "#{name}: deterministic setup has no move" if actions.empty?

    selected = actions[(index * 7 + salt) % actions.length]
    raise "#{name}: deterministic setup rejected a legal move" if environment.step(selected, actor: actor) != :ok
  end
  [game, environment]
end

def choose_checkers_move(game, environment)
  actor = environment.active_actor
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  choice = game.bot_strategy.choose(
    actions: environment.legal_actions(actor),
    observation: environment.observation(actor),
    actor: actor,
    random_source: environment.random_source,
    game: game,
    replay: environment.replay,
    context: environment.context,
    simulation: environment
  )
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  [choice, elapsed, game.bot_strategy.last_stats]
end

def exact_checkers_value(game, environment, action, depth: 7)
  actor = environment.active_actor
  branch = environment.fork_for_search
  raise "the quality reference move was rejected" if branch.step_for_search(action, actor: actor) != :ok

  strategy = game.bot_strategy
  strategy.instance_variable_set(:@search_cache_hits, 0)
  strategy.instance_variable_set(:@search_cutoffs, 0)
  strategy.send(
    :search,
    branch,
    depth - 1,
    -Float::INFINITY,
    Float::INFINITY,
    actor,
    game,
    environment.context,
    GameRoomBots::SearchBudget.new(limit: 1_000_000),
    {},
    {}
  )
end

def comparable_checkers_state(state)
  state.reject { |key, _value| key == :options }
end

# The in-memory transition used only by tree search must remain bit-for-bit
# equivalent to the normal event/replay path for every legal branch sampled.
transition_count = 0
[8, 10, 12].each_with_index do |size, size_index|
  game, environment = deterministic_checkers_environment(
    name: "transition-#{size}",
    size: size,
    plies: 0,
    salt: size_index,
    seed: 1_200 + size_index
  )
  20.times do |ply|
    break if environment.finished?

    actor = environment.active_actor
    actions = environment.legal_actions(actor)
    actions.each do |action|
      normal = environment.fork
      fast = environment.fork_for_search
      assert(normal.step(action, actor: actor) == :ok, "normal checkers transition rejected a legal move")
      assert(fast.step_for_search(action, actor: actor) == :ok, "fast checkers transition rejected a legal move")
      assert(
        comparable_checkers_state(normal.replay.state) == comparable_checkers_state(fast.replay.state),
        "fast checkers transition changed the resulting rule state"
      )
      transition_count += 1
    end

    ordered = actions.sort_by { |action| game.bot_action_key(action) }
    selected = ordered[(ply * 5 + size_index) % ordered.length]
    assert(environment.step(selected, actor: actor) == :ok, "transition setup could not advance")
  end
end

# These are decisions recorded from build 182 before the optimization. A new
# move is accepted only if a full-width depth-seven comparison proves that it
# has at least the same minimax value under the CURRENT evaluation function.
# After audit 212 this is a guard against regressing old candidate moves,
# not a claim that the evaluation or the depth-boundary rules never changed.
quality_cases = [
  {
    name: "classic opening",
    size: 8,
    plies: 0,
    salt: 0,
    seed: 900,
    previous: { "kind" => "piece_board", "action" => "move", "from_x" => 1, "from_y" => 2, "to_x" => 2, "to_y" => 3 }
  },
  {
    name: "classic forced capture",
    size: 8,
    plies: 14,
    salt: 3,
    seed: 901,
    previous: { "kind" => "piece_board", "action" => "move", "from_x" => 4, "from_y" => 3, "to_x" => 2, "to_y" => 5, "capture" => "3,4" }
  },
  {
    name: "international middle game",
    size: 10,
    plies: 16,
    salt: 5,
    seed: 902,
    previous: { "kind" => "piece_board", "action" => "move", "from_x" => 4, "from_y" => 1, "to_x" => 3, "to_y" => 2 }
  },
  {
    name: "twelve by twelve middle game",
    size: 12,
    plies: 12,
    salt: 2,
    seed: 903,
    previous: { "kind" => "piece_board", "action" => "move", "from_x" => 4, "from_y" => 5, "to_x" => 5, "to_y" => 6 }
  }
]

quality_cases.each do |item|
  game, environment = deterministic_checkers_environment(**item.reject { |key, _value| key == :previous })
  previous = reflect_checkers_action(item[:previous], item[:size])
  choice, elapsed, stats = choose_checkers_move(game, environment)
  assert(choice != nil, "#{item[:name]}: optimized bot returned no move")
  assert(environment.legal_actions(environment.active_actor).include?(choice), "#{item[:name]}: optimized bot returned an illegal move")
  if environment.legal_actions(environment.active_actor).length > 1
    assert(stats[:completed_depth] == 7, "#{item[:name]}: optimized bot did not complete depth seven")
  end

  if choice != previous
    previous_value = exact_checkers_value(game, environment, previous)
    optimized_value = exact_checkers_value(game, environment, choice)
    assert(
      optimized_value >= previous_value,
      "#{item[:name]}: optimized move value #{optimized_value} is below previous value #{previous_value}"
    )
  end
  puts "#{item[:name]}: #{format('%.3f', elapsed)} seconds; #{stats.inspect}"
end

puts "Checkers optimization quality test passed; #{transition_count} exact transitions compared"
