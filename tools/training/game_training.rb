require_relative 'match_runner'
require_relative "learned_strategy"
require "json"
require_relative "../../lib/game_simulation"

module GameRoomTraining
  TrainingReport = Struct.new(:episodes, :wins, :draws, :unfinished, :average_actions, keyword_init: true)
  TournamentReport = Struct.new(:ratings, :wins, :draws, :unfinished, :matches, :results, keyword_init: true)

  class PolicyTable
    def initialize(data = nil)
      @states = data.is_a?(Hash) ? normalize(data) : {}
    end

    def known_state?(state_key)
      @states.key?(state_key.to_s) && !@states[state_key.to_s].empty?
    end

    def value(state_key, action_key)
      entry = @states.dig(state_key.to_s, action_key.to_s)
      entry == nil ? 0.0 : entry["value"].to_f
    end

    def visits(state_key, action_key)
      entry = @states.dig(state_key.to_s, action_key.to_s)
      entry == nil ? 0 : entry["visits"].to_i
    end

    def update(state_key, action_key, reward)
      state = (@states[state_key.to_s] ||= {})
      entry = (state[action_key.to_s] ||= { "value" => 0.0, "visits" => 0 })
      count = entry["visits"].to_i + 1
      current = entry["value"].to_f
      entry["value"] = current + (reward.to_f - current) / count
      entry["visits"] = count
      entry["value"]
    end

    def best_action(state_key, actions)
      choices = actions.to_a
      choices.max_by do |action|
        key = block_given? ? yield(action) : action.to_s
        [value(state_key, key), visits(state_key, key)]
      end
    end

    def state_count
      @states.length
    end

    def decision_count
      @states.values.sum(&:length)
    end

    def to_h
      Marshal.load(Marshal.dump(@states))
    end

    def to_json(*arguments)
      JSON.generate(@states, *arguments)
    end

    def self.from_json(value)
      new(JSON.parse(value.to_s))
    end

    private

    def normalize(data)
      data.each_with_object({}) do |(state, actions), result|
        result[state.to_s] = actions.to_h.each_with_object({}) do |(action, entry), values|
          values[action.to_s] = {
            "value" => entry.to_h["value"].to_f,
            "visits" => entry.to_h["visits"].to_i
          }
        end
      end
    end
  end

  class SelfPlayTrainer
    attr_reader :policy

    def initialize(game:, players: nil, options: nil, policy: PolicyTable.new, epsilon: 0.15, max_actions: 10_000)
      @game = game
      @players = players || GameRoomParticipants.bots_for(1, game.minimum_players)
      @options = options
      @policy = policy
      @epsilon = epsilon
      @max_actions = max_actions
    end

    def train(episodes:, seed: 1)
      wins = Hash.new(0)
      draws = 0
      unfinished = 0
      actions = 0
      episodes.to_i.times do |offset|
        strategies = @players.each_with_object({}) do |actor, result|
          result[actor] = GameRoomBots::LearnedStrategy.new(
            policy: @policy,
            epsilon: @epsilon
          )
        end
        match = GameRoomSimulation::MatchRunner.new(
          game: @game,
          players: @players,
          options: @options,
          strategies: strategies,
          max_actions: @max_actions
        ).run(seed: seed.to_i + offset)
        actions += match.actions.to_i
        if !match.finished?
          unfinished += 1
        elsif match.draw
          draws += 1
        else
          wins[match.winner.to_s] += 1
        end
      end
      count = [episodes.to_i, 1].max
      TrainingReport.new(
        episodes: episodes.to_i,
        wins: wins,
        draws: draws,
        unfinished: unfinished,
        average_actions: actions.to_f / count
      )
    end
  end

  class EloRatings
    attr_reader :ratings

    def initialize(initial: 1_000.0, k_factor: 24.0)
      @initial = initial.to_f
      @k_factor = k_factor.to_f
      @ratings = {}
    end

    def rating(name)
      @ratings[name.to_s] ||= @initial
    end

    def record(first, second, first_score)
      first_rating = rating(first)
      second_rating = rating(second)
      expected = 1.0 / (1.0 + 10.0**((second_rating - first_rating) / 400.0))
      change = @k_factor * (first_score.to_f - expected)
      @ratings[first.to_s] = first_rating + change
      @ratings[second.to_s] = second_rating - change
    end
  end

  # A two-player round robin swaps seats on every seed. Multiplayer games can
  # be evaluated by passing explicit lineups to run_lineups.
  class Tournament
    def initialize(game:, competitors:, options: nil, max_actions: 10_000)
      @game = game
      @competitors = competitors.to_h
      @options = options
      @max_actions = max_actions
    end

    def run(seeds: [1])
      raise ArgumentError, "the standard tournament requires a two-player game" if @game.minimum_players != 2

      lineups = []
      names = @competitors.keys
      names.combination(2).each do |first, second|
        seeds.each do |seed|
          lineups << { names: [first, second], seed: seed.to_i }
          lineups << { names: [second, first], seed: seed.to_i }
        end
      end
      run_lineups(lineups)
    end

    def run_lineups(lineups)
      elo = EloRatings.new
      wins = Hash.new(0)
      draws = 0
      unfinished = 0
      results = []
      lineups.each do |lineup|
        names = lineup.fetch(:names).map(&:to_s)
        players = GameRoomParticipants.bots_for(1, names.length)
        strategies = players.each_with_index.each_with_object({}) do |(actor, index), mapping|
          mapping[actor] = @competitors.fetch(names[index])
        end
        result = GameRoomSimulation::MatchRunner.new(
          game: @game,
          players: players,
          options: @options,
          strategies: strategies,
          max_actions: @max_actions
        ).run(seed: lineup.fetch(:seed).to_i)
        results << { lineup: names, result: result }
        if !result.finished?
          unfinished += 1
        elsif result.draw
          draws += 1
          elo.record(names[0], names[1], 0.5) if names.length == 2
        else
          winner_index = players.index { |player| GameRoomParticipants.same?(player, result.winner) }
          winner_name = winner_index == nil ? result.winner.to_s : names[winner_index]
          wins[winner_name] += 1
          if names.length == 2
            elo.record(names[0], names[1], winner_index == 0 ? 1.0 : 0.0)
          end
        end
      end
      TournamentReport.new(
        ratings: elo.ratings.dup,
        wins: wins,
        draws: draws,
        unfinished: unfinished,
        matches: results.length,
        results: results
      )
    end
  end
end
