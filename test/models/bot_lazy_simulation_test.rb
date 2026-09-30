require_relative "../support/elten_array_shuffle"
require_relative "../support/new_games_fixture"
require_relative "../../lib/game_execution_policy"
require_relative "../../games/tic_tac_toe"
require_relative "../../games/four_in_a_row"
require_relative "../../games/farkle"
require_relative "../../games/ninety_nine"
require_relative "../../games/tysiac"
require_relative "../../games/spades"
require_relative "../../games/cat_head_tail"
require_relative "../../games/quiz_party"

module BotSnapshotCount
  attr_accessor :snapshot_count

  def from_snapshot(**args)
    self.snapshot_count = snapshot_count.to_i + 1
    super
  end
end
GameRoomSimulation::Environment.singleton_class.prepend(BotSnapshotCount)

def snapshot_decision(type, seed, eager)
  game = type.new
  environment = GameRoomSimulation::Environment.new_game(game: game, players: %w[Alice Bob], seed: seed)
  repository = environment.repository
  def repository.session_id(session); session["__id"]; end
  replay = environment.replay
  source_before = Marshal.dump([environment.session, environment.events, replay])
  private_context = Object.new
  context = GameRoomGames::ActionContext.new(
    random_source: GameRoomRandom::SeededSource.new(seed + 500),
    hidden_submissions: private_context, now: 1_800_000_000
  )
  calls = 0
  original = game.method(:replay)
  game.define_singleton_method(:replay) do |*args, **kwargs|
    calls += 1
    original.call(*args, **kwargs)
  end
  coordinator = GameRoomBots::Coordinator.new
  GameRoomSimulation::Environment.snapshot_count = 0
  decision = if eager
    simulation = GameRoomSimulation::Environment.from_snapshot(
      game: game, session: environment.session, events: replay.accepted_events,
      players: environment.players, seed: GameRoomExecutionPolicy.bot_seed(repository, environment.session, replay)
    )
    coordinator.decide_next(game: game, replay: replay, context: context,
      simulation: simulation, controlled_actors: environment.players)
  else
    GameRoomExecutionPolicy.bot_decision(game: game, session: environment.session,
      replay: replay, repository: repository, coordinator: coordinator, context: context,
      players: environment.players, controlled_actors: environment.players)
  end
  assert(source_before == Marshal.dump([environment.session, environment.events, replay]), "decision mutated live snapshot")
  assert(context.hidden_submissions.equal?(private_context), "decision replaced private action context")
  strategy = game.bot_strategy
  stats = if strategy.respond_to?(:last_stats)
    strategy.last_stats.reject { |key, _| key == :cooperative_yields }
  elsif game.is_a?(GameRoomGames::Mancala)
    game.strategy_for(game.skill(replay.state)).last_stats.reject { |key, _| key == :cooperative_yields }
  end
  { decision: decision&.action, actor: decision&.actor, available: decision&.available_actions,
    next_random: context.random_source.roll(count: 3, sides: 100).values,
    replay_calls: calls, snapshots: GameRoomSimulation::Environment.snapshot_count, stats: stats }
end

comparisons = 0
[GameRoomGames::Uno, GameRoomGames::Makao, GameRoomGames::Monopoly].each do |type|
  [1, 5, 17].each do |seed|
    before, after = snapshot_decision(type, seed, true), snapshot_decision(type, seed, false)
    assert(before[:decision], "#{type} did not make a comparison decision")
    assert(before.reject { |key, _| [:replay_calls, :snapshots].include?(key) } ==
      after.reject { |key, _| [:replay_calls, :snapshots].include?(key) }, "#{type} action/RNG changed")
    assert(before[:snapshots] == 1 && after[:snapshots] == 0, "#{type} still builds unused simulation")
    assert(before[:replay_calls] == after[:replay_calls] + 1, "#{type} did not remove exactly one replay")
    comparisons += 1
  end
end

[GameRoomGames::TicTacToe, GameRoomGames::FourInARow, GameRoomGames::Mancala].each do |type|
  before, after = snapshot_decision(type, 7, true), snapshot_decision(type, 7, false)
  assert(before == after && after[:decision], "#{type} search, budget, RNG or simulation changed")
  assert(after[:snapshots] == 1 && after[:stats][:nodes].to_i > 0, "#{type} silently fell back without search")
  comparisons += 1
end

# Every production strategy declares whether it uses a full environment.
replay_only = [GameRoomBots::RandomStrategy.new, GameRoomBots::HeuristicStrategy.new,
  BibliosPlanning::Strategy.new, BattleshipPlanning::Strategy.new, FarklePlanning::Strategy.new,
  CatHeadTailPlanning::Strategy.new, NinetyNinePlanning::Strategy.new, TysiacPlanning::Strategy.new,
  SpadesLearning::Strategy.new, GameRoomGames::QuizParty::BotStrategy.new(knowledge_percent: 50)]
assert(replay_only.all? { |strategy| strategy.simulation_required? == false }, "replay-only capability missing")

# Private phases retain the original ActionContext. The factory must not even
# read/copy the full secret state for a replay-only strategy.
game = GameRoomGames::Battleship.new
environment = GameRoomSimulation::Environment.new_game(game: game,
  players: GameRoomParticipants.bots_for(5, 2), seed: 1)
private_context = Object.new
context = GameRoomGames::ActionContext.new(random_source: GameRoomRandom::SeededSource.new(4), hidden_submissions: private_context)
strategy = Class.new do
  include GameRoomBots::ReplayOnlyStrategy
  attr_reader :received_context
  def choose(actions:, context:, **_extra)
    @received_context = context
    actions.first
  end
end.new
coordinator = GameRoomBots::Coordinator.new
decision = coordinator.decide_next(game: game, replay: environment.replay, context: context,
  strategy: strategy, controlled_actors: environment.players,
  simulation_factory: -> { raise "private replay-only decision requested a simulation" })
assert(decision && strategy.received_context.equal?(context), "private decision lost its original context")

# Existing external strategies have no capability hook. Keep passing a real
# Environment, not a proxy/factory, and retain the old four-keyword adapter.
game = GameRoomGames::TicTacToe.new
environment = GameRoomSimulation::Environment.new_game(game: game, players: %w[Alice Bob], seed: 5)
context = environment.context
external = Class.new do
  attr_reader :received
  def choose(actions:, simulation:, **_extra)
    @received = simulation
    actions.first
  end
end.new
calls = 0
factory = -> { calls += 1; environment }
coordinator.decide_next(game: game, replay: environment.replay, context: context,
  controlled_actors: environment.players, strategy: external, simulation_factory: factory)
assert(calls == 1 && external.received.equal?(environment), "external strategy compatibility broken")
legacy = Class.new do
  def choose(actions:, observation:, actor:, random_source:)
    actions.first
  end
end.new
assert(coordinator.decide_next(game: game, replay: environment.replay, context: context,
  controlled_actors: environment.players, strategy: legacy, simulation_factory: factory), "legacy strategy keywords broken")
coordinator.decide_next(game: game, replay: environment.replay, context: context,
  controlled_actors: environment.players, strategy: external, simulation: environment,
  simulation_factory: -> { raise "explicit simulation was replaced" })

# Multiple eligible actors may be considered if one declines. ExecutionPolicy
# owns one memoized factory per decision, not a cache shared between decisions.
game.define_singleton_method(:active_actors) { |_replay| %w[Alice Bob] }
game.define_singleton_method(:legal_actions) { |_replay, _actor, context:| [{ "action" => "place", "x" => 1, "y" => 1 }] }
strategy = Class.new do
  def choose(actions:, actor:, simulation:, **_extra)
    raise "factory did not supply environment" unless simulation.is_a?(GameRoomSimulation::Environment)
    actor == "Bob" ? actions.first : nil
  end
end.new
game.define_singleton_method(:bot_strategy) { strategy }
repository = environment.repository
def repository.session_id(session); session["__id"]; end
GameRoomSimulation::Environment.snapshot_count = 0
2.times do
  decision = GameRoomExecutionPolicy.bot_decision(game: game, session: environment.session,
    replay: environment.replay, repository: repository, coordinator: coordinator, context: context,
    players: environment.players, controlled_actors: environment.players)
  assert(decision.actor == "Bob", "declining actor blocked the next candidate")
end
assert(GameRoomSimulation::Environment.snapshot_count == 2, "factory repeated per actor or leaked between decisions")
game.define_singleton_method(:legal_actions) { |_replay, _actor, context:| [] }
coordinator.decide_next(game: game, replay: environment.replay, context: context,
  controlled_actors: environment.players, simulation_factory: -> { raise "no-action decision built simulation" })

puts "PASS lazy bot simulation: #{comparisons} eager/lazy action, RNG and search comparisons; private context, external/legacy strategies, no-action and per-decision factory lifetime"
