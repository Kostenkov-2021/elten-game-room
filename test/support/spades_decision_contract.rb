require_relative 'contract_values'

module GameRoomTest
  module SpadesDecisionContract
    module_function

    def capture(game, item)
      [false, true].flat_map do |omniscient|
        [1, 3, 7, 13, 17].map do |length|
          session = item.fetch('session').merge('options' => JSON.generate(item.fetch('options').merge('omniscient_bots' => omniscient)))
          env = GameRoomSimulation::Environment.new(game: game, session: session,
            events: item.fetch('events').first(length), players: item.fetch('players'),
            random_source: GameRoomRandom::SeededSource.new(241))
          actor = env.active_actor
          decision = GameRoomBots::Coordinator.new.decide(game: game, replay: env.replay, actor: actor,
            context: env.context, simulation_factory: -> { env.fork }, controlled_actors: [actor])
          { 'events' => length, 'omniscient' => omniscient, 'actor' => actor,
            'available' => decision.available_actions, 'action' => decision.action,
            'rng' => env.random_source.roll(count: 8, sides: 1000).values }
        end
      end
    end
  end
end
