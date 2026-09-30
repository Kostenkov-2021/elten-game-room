require_relative "../../../lib/game_simulation"
require_relative "../../../games/spades"

def assert(value, message)
  raise message unless value
end

module Log
  def self.warning(message)
    (@warnings ||= []) << message
  end
  def self.warnings; @warnings ||= []; end
end

game = GameRoomGames::Spades.new
env = GameRoomSimulation::Environment.new_game(game: game, players: %w[A B C], seed: 71)
while env.replay.state[:phase] == :bidding
  actor = env.active_actor
  bid = env.legal_actions(actor).find { |action| action['bid'] == 1 } || env.legal_actions(actor).first
  assert(env.step(bid, actor: actor) == :ok, 'setup rejected')
end
state, actor = env.replay.state, env.active_actor
planner = SpadesPlanning::RoundPlanner.new(game)
information = game.bot_decision_context(env.replay, actor)
# Missing optional historical evidence retains the ordinary soft likelihood.
weight = planner.send(:world_likelihood, state, actor, {})
assert(weight.between?(0.15, 1.0), 'absent optional history is rejected')

def game.estimated_bot_bid(*)
  raise NoMethodError, 'test: internal likelihood estimator fault'
end
2.times do
  result = planner.plan(state: state, actor: actor, information: information)
  assert(result[:scores].empty?, 'internal fault was used as a plausible world')
  assert(planner.last_failure[:type] == 'NoMethodError', 'internal error was not diagnosed')
end
assert(Log.warnings.length == 1 && Log.warnings.first.include?('internal likelihood estimator fault'), 'fallback diagnostic missing or repeated')
game.singleton_class.send(:remove_method, :estimated_bot_bid)
result = planner.plan(state: state, actor: actor, information: information)
assert(!result[:scores].empty? && planner.last_failure.nil?, 'valid subsequent analysis cannot recover')
puts 'Spades likelihood: absent optional evidence accepted; internal fault reaches diagnosed/deduplicated fallback; later valid analysis recovers'
