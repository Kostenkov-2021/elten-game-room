require_relative 'assertions'
require_relative 'contract_values'

module GameRoomTest
  module ModelContract
    extend Assertions
    module_function

    def players_for(game, options)
      count = (game.minimum_players..game.maximum_players).find do |size|
        !game.validation_error(options, player_count: size)
      end
      raise "No valid default roster: #{game.id}" unless count
      %w[Alice Bob Carol Dave Eve Frank Grace Heidi].first(count)
    end

    def check_replay(env)
      inputs = ContractValues.digest([env.session, env.events])
      full = env.game.replay(env.session, env.events, env.repository)
      assert_equal(ContractValues.canonical(full), ContractValues.canonical(env.replay), "#{env.game.id}: incremental replay differs")
      assert_equal(inputs, ContractValues.digest([env.session, env.events]), "#{env.game.id}: replay changed input")
      assert_equal(env.events, full.accepted_events, "#{env.game.id}: generated event rejected")
      unknown = {'__id' => 2_000_000_000, 'actor' => 'Unknown participant',
        'action' => '__unknown_contract_event__', 'value' => '', 'created_at' => 0}
      rejected = env.game.replay(env.session, env.events + [unknown], env.repository)
      assert_equal(ContractValues.canonical(full), ContractValues.canonical(rejected), "#{env.game.id}: rejected event mutated replay")
      full
    end

    def checkpoint(env)
      replay = check_replay(env)
      actor = env.active_actor
      actions = env.legal_actions(actor)
      { 'events' => env.events.length, 'replay' => ContractValues.digest(replay),
        'actor' => actor, 'legal' => ContractValues.digest(actions),
        'rng' => env.random_source.dup.roll(count: 8, sides: 1000).values }
    end
  end
end
