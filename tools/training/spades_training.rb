require_relative 'match_runner'
require_relative '../../lib/spades_learning'

module SpadesLearning
  TrainingReport = Struct.new(:policy, :generations, :accepted, :history, keyword_init: true)
  Evaluation = Struct.new(
    :games, :wins, :losses, :neutral_wins, :average_reward,
    :average_margin, :average_actions, :average_rounds,
    :bid_accuracy_margin, :candidate_bid_error,
    :opponent_bid_error, :candidate_bid_bias, :opponent_bid_bias,
    :candidate_contract_rate, :opponent_contract_rate,
    :candidate_average_overtricks, :opponent_average_overtricks,
    :candidate_average_shortfall, :opponent_average_shortfall,
    :average_table_bid_gap, :average_table_bid_deficit,
    :incomplete_games, :scenarios,
    keyword_init: true
  ) do
    def policy_quality(role, quicksand:)
      contract_rate = public_send("#{role}_contract_rate").to_f
      bid_error = public_send("#{role}_bid_error").to_f
      bid_bias = public_send("#{role}_bid_bias").to_f.abs
      overtricks = public_send("#{role}_average_overtricks").to_f
      shortfall = public_send("#{role}_average_shortfall").to_f
      overtrick_cost = quicksand ? 0.55 : 0.14
      contract_rate * 2.0 - bid_error * 0.35 - bid_bias * 0.45 -
        overtricks * overtrick_cost - shortfall * 0.45
    end

    def quality_advantage(quicksand:)
      policy_quality(:candidate, quicksand: quicksand) -
        policy_quality(:opponent, quicksand: quicksand)
    end
  end
  CampaignReport = Struct.new(
    :profile, :policy, :series, :accepted_series, :plateau, :history,
    keyword_init: true
  )

  Scenario = Struct.new(
    :id, :player_count, :team_size, :score_limit, :quicksand,
    keyword_init: true
  ) do
    def team?
      team_size.to_i > 0
    end

    def unit_count
      team? ? player_count.to_i / team_size.to_i : player_count.to_i
    end

    def rotation_count
      unit_count
    end

    def options
      {
        "score_limit" => score_limit.to_i,
        "team_size" => team_size.to_i,
        "quicksand" => quicksand == true
      }
    end

    def profile
      "#{quicksand == true ? 'quicksand' : 'standard'}_#{team? ? 'team' : 'individual'}"
    end
  end

  module ScenarioMatrix
    module_function

    INDIVIDUAL_COUNTS = [3, 4, 5, 6].freeze
    TEAM_ARRANGEMENTS = [[4, 2], [6, 2], [6, 3]].freeze
    # Full 300-point matches are the strategic reference. Short matches often
    # end before standard bags reach the -100 penalty and therefore reward
    # locally profitable but globally poor overtricks.
    TRAINING_SCORE_LIMITS = [300].freeze
    BENCHMARK_SCORE_LIMITS = [300].freeze
    DEFAULT_SCORE_LIMITS = BENCHMARK_SCORE_LIMITS

    def for_profile(profile, score_limits: DEFAULT_SCORE_LIMITS)
      key = profile.to_s
      raise ArgumentError, "unknown Spades profile: #{profile}" if !PROFILE_KEYS.include?(key)

      quicksand = key.start_with?("quicksand")
      arrangements = if key.end_with?("team")
        TEAM_ARRANGEMENTS
      else
        INDIVIDUAL_COUNTS.map { |count| [count, 0] }
      end
      score_limits.to_a.map(&:to_i).uniq.flat_map do |score_limit|
        arrangements.map do |player_count, team_size|
          Scenario.new(
            id: [key, "p#{player_count}", "t#{team_size}", "s#{score_limit}"].join("-"),
            player_count: player_count,
            team_size: team_size,
            score_limit: score_limit,
            quicksand: quicksand
          )
        end
      end
    end

    def for_arrangement(profile, player_count:, team_size:, score_limits: DEFAULT_SCORE_LIMITS)
      key = profile.to_s
      raise ArgumentError, "unknown Spades profile: #{profile}" if !PROFILE_KEYS.include?(key)

      quicksand = key.start_with?("quicksand")
      score_limits.to_a.map(&:to_i).uniq.map do |score_limit|
        Scenario.new(
          id: [key, "p#{player_count}", "t#{team_size}", "s#{score_limit}"].join("-"),
          player_count: player_count.to_i,
          team_size: team_size.to_i,
          score_limit: score_limit,
          quicksand: quicksand
        )
      end
    end
  end

  class Arena
    attr_reader :scenarios

    def initialize(game:, score_limit: 100, max_actions: 6_000, scenarios: nil, profile: nil, score_limits: nil)
      @game = game
      @max_actions = max_actions.to_i
      @scenarios = if scenarios != nil
        scenarios.to_a
      elsif profile != nil
        ScenarioMatrix.for_profile(profile, score_limits: score_limits || [score_limit])
      else
        legacy_scenarios(score_limit)
      end
      raise ArgumentError, "Spades arena requires at least one scenario" if @scenarios.empty?
    end

    def compare(candidate:, opponent:, seeds:)
      rewards = []
      margins = []
      candidate_bid_error = 0.0
      opponent_bid_error = 0.0
      candidate_bid_bias = 0.0
      opponent_bid_bias = 0.0
      candidate_bid_count = 0
      opponent_bid_count = 0
      table_bid_gap = 0.0
      table_bid_deficit = 0.0
      completed_rounds = 0
      contract_totals = {
        candidate_contracts: 0, candidate_contracts_made: 0,
        candidate_overtricks: 0, candidate_shortfall: 0,
        opponent_contracts: 0, opponent_contracts_made: 0,
        opponent_overtricks: 0, opponent_shortfall: 0
      }
      total_actions = 0
      total_match_rounds = 0
      wins = 0
      incomplete_games = 0
      scenario_results = {}
      seeds.to_a.each do |seed|
        @scenarios.each_with_index do |scenario, scenario_index|
          scenario_rewards = []
          scenario_margins = []
          scenario_incomplete = 0
          scenario_seed = seed.to_i + scenario_index * 1_000_003
          scenario.unit_count.times do |candidate_unit|
            result, candidate_players = match_for(
              scenario, candidate, opponent, scenario_seed, candidate_unit
            )
            reward = outcome_reward(result, candidate_players)
            margin = score_margin(result, candidate_players, scenario.score_limit)
            bidding = bidding_metrics(result, candidate_players, scenario)
            total_actions += result.actions.to_i
            total_match_rounds += result.events.to_a.count { |event| event["action"].to_s == "deal" }
            rewards << reward
            margins << margin
            scenario_rewards << reward
            scenario_margins << margin
            candidate_bid_error += bidding[:candidate_error]
            opponent_bid_error += bidding[:opponent_error]
            candidate_bid_bias += bidding[:candidate_bias]
            opponent_bid_bias += bidding[:opponent_bias]
            candidate_bid_count += bidding[:candidate_count]
            opponent_bid_count += bidding[:opponent_count]
            table_bid_gap += bidding[:table_gap]
            table_bid_deficit += bidding[:table_deficit]
            completed_rounds += bidding[:rounds]
            contract_totals.each_key do |name|
              contract_totals[name] += bidding[name]
            end
            wins += 1 if reward > 0
            incomplete_games += 1 if !result.finished?
            scenario_incomplete += 1 if !result.finished?
          end
          entry = scenario_results[scenario.id] ||= {
            profile: scenario.profile,
            player_count: scenario.player_count,
            team_size: scenario.team_size,
            score_limit: scenario.score_limit,
            games: 0,
            wins: 0,
            neutral_wins: 0,
            incomplete_games: 0,
            margins: []
          }
          entry[:games] += scenario_rewards.length
          entry[:wins] += scenario_rewards.count { |reward| reward > 0 }
          entry[:neutral_wins] += 1
          entry[:incomplete_games] += scenario_incomplete
          entry[:margins].concat(scenario_margins)
        end
      end
      Evaluation.new(
        games: rewards.length,
        wins: wins,
        losses: rewards.length - wins,
        neutral_wins: seeds.to_a.length * @scenarios.length,
        average_reward: rewards.empty? ? 0.0 : rewards.sum.to_f / rewards.length,
        average_margin: margins.empty? ? 0.0 : margins.sum.to_f / margins.length,
        average_actions: rewards.empty? ? 0.0 : total_actions.to_f / rewards.length,
        average_rounds: rewards.empty? ? 0.0 : total_match_rounds.to_f / rewards.length,
        candidate_bid_error: candidate_bid_count == 0 ? 0.0 : candidate_bid_error / candidate_bid_count,
        opponent_bid_error: opponent_bid_count == 0 ? 0.0 : opponent_bid_error / opponent_bid_count,
        candidate_bid_bias: candidate_bid_count == 0 ? 0.0 : candidate_bid_bias / candidate_bid_count,
        opponent_bid_bias: opponent_bid_count == 0 ? 0.0 : opponent_bid_bias / opponent_bid_count,
        candidate_contract_rate: ratio(
          contract_totals[:candidate_contracts_made], contract_totals[:candidate_contracts]
        ),
        opponent_contract_rate: ratio(
          contract_totals[:opponent_contracts_made], contract_totals[:opponent_contracts]
        ),
        candidate_average_overtricks: ratio(
          contract_totals[:candidate_overtricks], contract_totals[:candidate_contracts]
        ),
        opponent_average_overtricks: ratio(
          contract_totals[:opponent_overtricks], contract_totals[:opponent_contracts]
        ),
        candidate_average_shortfall: ratio(
          contract_totals[:candidate_shortfall], contract_totals[:candidate_contracts]
        ),
        opponent_average_shortfall: ratio(
          contract_totals[:opponent_shortfall], contract_totals[:opponent_contracts]
        ),
        bid_accuracy_margin: if candidate_bid_count == 0 || opponent_bid_count == 0
          0.0
        else
          opponent_bid_error / opponent_bid_count - candidate_bid_error / candidate_bid_count
        end,
        average_table_bid_gap: completed_rounds == 0 ? 0.0 : table_bid_gap / completed_rounds,
        average_table_bid_deficit: completed_rounds == 0 ? 0.0 : table_bid_deficit / completed_rounds,
        incomplete_games: incomplete_games,
        scenarios: scenario_results.transform_values do |entry|
          values = entry.dup
          scenario_margins = values.delete(:margins)
          values[:losses] = values[:games] - values[:wins]
          values[:average_margin] = scenario_margins.empty? ? 0.0 : scenario_margins.sum.to_f / scenario_margins.length
          values
        end
      )
    end

    private

    def bidding_metrics(result, candidate_players, scenario)
      totals = {
        candidate_error: 0.0, opponent_error: 0.0,
        candidate_bias: 0.0, opponent_bias: 0.0,
        candidate_count: 0, opponent_count: 0,
        candidate_contracts: 0, candidate_contracts_made: 0,
        candidate_overtricks: 0, candidate_shortfall: 0,
        opponent_contracts: 0, opponent_contracts_made: 0,
        opponent_overtricks: 0, opponent_shortfall: 0,
        table_gap: 0.0, table_deficit: 0.0, rounds: 0
      }
      bids = {}
      tricks = Hash.new(0)
      trick = []
      expected_tricks = @game.send(:cards_per_player, scenario.player_count)
      finish_round = lambda do
        complete = bids.length == scenario.player_count && trick.empty? && tricks.values.sum == expected_tricks
        if complete
          bids.each do |player, bid|
            error = (bid.to_i - tricks.fetch(player, 0).to_i).abs
            bias = bid.to_i - tricks.fetch(player, 0).to_i
            if candidate_players.any? { |candidate| GameRoomParticipants.same?(candidate, player) }
              totals[:candidate_error] += error
              totals[:candidate_bias] += bias
              totals[:candidate_count] += 1
            else
              totals[:opponent_error] += error
              totals[:opponent_bias] += bias
              totals[:opponent_count] += 1
            end
          end
          assignment = @game.team_assignment(scenario.options, players: result.players)
          units = if assignment == nil
            result.players.map { |player| [player] }
          else
            assignment.team_ids.map { |team| assignment.members_for(team) }
          end
          units.each do |members|
            regular = members.reject { |player| bids.fetch(player, -1).to_i == 0 }
            next if regular.empty?

            prefix = members.any? do |member|
              candidate_players.any? { |candidate| GameRoomParticipants.same?(member, candidate) }
            end ? :candidate : :opponent
            contract = regular.sum { |player| bids.fetch(player, 0).to_i }
            won = regular.sum { |player| tricks.fetch(player, 0).to_i }
            totals[:"#{prefix}_contracts"] += 1
            totals[:"#{prefix}_contracts_made"] += 1 if won >= contract
            totals[:"#{prefix}_overtricks"] += [won - contract, 0].max
            totals[:"#{prefix}_shortfall"] += [contract - won, 0].max
          end
          totals[:table_gap] += (expected_tricks - bids.values.sum(&:to_i)).abs
          totals[:table_deficit] += expected_tricks - bids.values.sum(&:to_i)
          totals[:rounds] += 1
        end
        bids = {}
        tricks = Hash.new(0)
        trick = []
      end

      result.events.to_a.each do |event|
        case event["action"].to_s
        when "deal"
          finish_round.call if !bids.empty? || !trick.empty? || !tricks.empty?
        when "bid"
          bids[event["actor"].to_s] = event["value"].to_i
        when "play"
          trick << { player: event["actor"].to_s, card: event["value"].to_s }
          if trick.length == scenario.player_count
            winner = @game.send(:trick_winner, trick)
            tricks[winner.to_s] += 1
            trick = []
          end
        end
      end
      finish_round.call if !bids.empty? || !trick.empty? || !tricks.empty?
      totals
    end

    def legacy_scenarios(score_limit)
      [
        Scenario.new(id: "legacy-team", player_count: 4, team_size: 2, score_limit: score_limit, quicksand: false),
        Scenario.new(id: "legacy-individual", player_count: 3, team_size: 0, score_limit: score_limit, quicksand: false)
      ]
    end

    def ratio(numerator, denominator)
      denominator.to_i == 0 ? 0.0 : numerator.to_f / denominator.to_i
    end

    def strategy(value)
      # Evolution tunes only policy weights. The complete-round planner is a
      # fixed shared layer and would multiply the cost of every candidate while
      # contributing the same algorithm on both sides. Final live-bot and
      # planner benchmarks exercise it separately.
      value.is_a?(Policy) ? Strategy.new(policy: value, round_planning: false) : value
    end

    def score_margin(result, candidate_players, score_limit)
      state = result.final_state
      scores = state == nil ? nil : state[:scores]
      return result.rewards.fetch(candidate_players.first) if !scores.is_a?(Hash) || scores.empty?

      assignment = @game.team_assignment(state[:options], players: result.players)
      if assignment == nil
        candidate_score = scores.fetch(candidate_players.first, 0).to_f
        opponents = result.players.reject { |player| candidate_players.include?(player) }
        opponent_score = opponents.sum { |player| scores.fetch(player, 0).to_f } / [opponents.length, 1].max
      else
        team = assignment.team_index_for(candidate_players.first)
        candidate_unit = "team:#{team}"
        candidate_score = scores.fetch(candidate_unit, 0).to_f
        opponent_scores = scores.reject { |unit, _score| unit.to_s == candidate_unit }.values.map(&:to_f)
        opponent_score = opponent_scores.sum / [opponent_scores.length, 1].max
      end
      (candidate_score - opponent_score) / [score_limit.to_i, 1].max.to_f
    end

    def outcome_reward(result, candidate_players)
      return result.rewards.fetch(candidate_players.first).to_f if result.finished?

      state = result.final_state
      scores = state == nil ? nil : state[:scores]
      return 0.0 if !scores.is_a?(Hash) || scores.empty?

      assignment = @game.team_assignment(state[:options], players: result.players)
      candidate_unit = if assignment == nil
        candidate_players.first
      else
        "team:#{assignment.team_index_for(candidate_players.first)}"
      end
      # A stable public tie-break keeps seat rotation neutral even when a
      # training episode stops between complete matches with equal scores.
      provisional_winner = scores.max_by { |unit, score| [score.to_i, unit.to_s] }&.first
      provisional_winner.to_s == candidate_unit.to_s ? 1.0 : -1.0
    end

    def match_for(scenario, candidate, opponent, seed, candidate_unit)
      players = GameRoomParticipants.bots_for(1, scenario.player_count)
      candidate_players = if scenario.team?
        assignment = GameRoomTeams::Assignment.new(players: players, team_size: scenario.team_size)
        assignment.members_for("team:#{candidate_unit}")
      else
        [players[candidate_unit]]
      end
      strategies = players.each_with_object({}) do |player, result|
        result[player] = candidate_players.include?(player) ? strategy(candidate) : strategy(opponent)
      end
      match = GameRoomSimulation::MatchRunner.new(
        game: @game,
        players: players,
        options: scenario.options,
        strategies: strategies,
        max_actions: @max_actions
      ).run(seed: seed)
      [match, candidate_players]
    end
  end

  class SelfPlayTrainer
    attr_reader :policy

    def initialize(game:, policy: Policy.default, seed: 1, score_limit: 100, scenarios: nil, profile: nil, score_limits: nil,
      max_actions: 6_000)
      @game = game
      @policy = policy
      @random = Random.new(seed.to_i)
      @seed = seed.to_i
      @arena = Arena.new(
        game: game, score_limit: score_limit, scenarios: scenarios,
        profile: profile, score_limits: score_limits, max_actions: max_actions
      )
    end

    def train(generations:, population: 6, evaluation_seeds: 4, mutation_scale: 0.7, accept_score_ties: true)
      history = []
      accepted = 0
      generations.to_i.times do |generation|
        seeds = Array.new(evaluation_seeds.to_i) do |index|
          @seed + generation * 10_000 + index * 97
        end
        neutral_wins = seeds.length * @arena.scenarios.length
        candidates = Array.new(population.to_i) do
          candidate = @policy.mutated(
            @random,
            scale: mutation_scale.to_f / Math.sqrt(generation + 1.0)
          )
          evaluation = @arena.compare(candidate: candidate, opponent: @policy, seeds: seeds)
          [candidate, evaluation]
        end
        quicksand = @arena.scenarios.all? { |scenario| scenario.quicksand == true }
        best_policy, best_evaluation = candidates.max_by do |_candidate, evaluation|
          [evaluation.wins - evaluation.neutral_wins, evaluation.average_margin,
            evaluation.quality_advantage(quicksand: quicksand),
            evaluation.bid_accuracy_margin, -evaluation.average_actions]
        end
        competitive_improvement = best_evaluation.wins > neutral_wins ||
          (accept_score_ties && best_evaluation.wins == neutral_wins && (
            best_evaluation.average_margin > 0.005 ||
            (best_evaluation.average_margin >= -0.005 && best_evaluation.bid_accuracy_margin > 0.05)
          ))
        # A policy cannot qualify merely by beating an opponent that shares a
        # severe absolute bidding defect. It must also complete every sampled
        # match and preserve contract quality, estimation accuracy and bag
        # control relative to the champion it is trying to replace.
        quality_advantage = best_evaluation.quality_advantage(quicksand: quicksand)
        improved = competitive_improvement && best_evaluation.incomplete_games == 0 &&
          quality_advantage >= -0.03
        if improved
          @policy = best_policy
          accepted += 1
        end
        entry = {
          generation: generation + 1,
          accepted: improved,
          reference_wins: neutral_wins,
          candidate_wins: best_evaluation.wins,
          candidate_margin: best_evaluation.average_margin,
          candidate_bid_accuracy_margin: best_evaluation.bid_accuracy_margin,
          candidate_quality_advantage: quality_advantage,
          candidate_contract_rate: best_evaluation.candidate_contract_rate,
          candidate_average_overtricks: best_evaluation.candidate_average_overtricks,
          candidate_average_shortfall: best_evaluation.candidate_average_shortfall,
          candidate_average_actions: best_evaluation.average_actions,
          candidate_average_rounds: best_evaluation.average_rounds,
          incomplete_games: best_evaluation.incomplete_games
        }
        history << entry
        yield(entry) if block_given?
      end
      TrainingReport.new(
        policy: @policy,
        generations: generations.to_i,
        accepted: accepted,
        history: history
      )
    end
  end

  # A series explores rotating scenario batches, then verifies the result on
  # two fresh full matrices. Three rejected full series form the plateau.
  class CampaignTrainer
    attr_reader :policy, :scenarios

    def initialize(game:, profile:, policy: nil, seed: 1, score_limits: ScenarioMatrix::TRAINING_SCORE_LIMITS,
      scenarios: nil)
      @game = game
      @profile = profile.to_s
      @policy = policy || Policy.strategic(@profile)
      @seed = seed.to_i
      @scenarios = scenarios || ScenarioMatrix.for_profile(@profile, score_limits: score_limits)
    end

    def train(max_series: 20, plateau_limit: 3, generations_per_series: 4, population: 6,
      scenarios_per_generation: 3, evaluation_seeds: 2, validation_seeds: 2,
      mutation_scale: 0.7, training_max_actions: 6_000, validation_max_actions: 6_000)
      history = []
      accepted_series = 0
      plateau = 0
      series_index = 0
      while series_index < max_series.to_i && plateau < plateau_limit.to_i
        series_index += 1
        champion = @policy
        candidate = @policy
        generation_history = []
        generations_per_series.to_i.times do |generation|
          start = ((series_index - 1) * generations_per_series.to_i + generation) * scenarios_per_generation.to_i
          batch = Array.new([scenarios_per_generation.to_i, @scenarios.length].min) do |offset|
            @scenarios[(start + offset) % @scenarios.length]
          end
          trainer = SelfPlayTrainer.new(
            game: @game,
            policy: candidate,
            seed: @seed + series_index * 1_000_000 + generation * 10_000,
            scenarios: batch,
            max_actions: training_max_actions
          )
          report = trainer.train(
            generations: 1,
            population: population,
            evaluation_seeds: evaluation_seeds,
            mutation_scale: mutation_scale,
            accept_score_ties: false
          )
          candidate = report.policy
          generation_history.concat(report.history)
        end

        validation_arena = Arena.new(game: @game, scenarios: @scenarios, max_actions: validation_max_actions)
        first_seeds = Array.new(validation_seeds.to_i) do |index|
          @seed + 50_000_000 + series_index * 100_000 + index * 131
        end
        second_seeds = Array.new(validation_seeds.to_i) do |index|
          @seed + 80_000_000 + series_index * 100_000 + index * 137
        end
        first = validation_arena.compare(candidate: candidate, opponent: champion, seeds: first_seeds)
        second = validation_arena.compare(candidate: candidate, opponent: champion, seeds: second_seeds)
        changed = candidate.weights != champion.weights
        quicksand = @scenarios.all? { |scenario| scenario.quicksand == true }
        first_quality = first.quality_advantage(quicksand: quicksand)
        second_quality = second.quality_advantage(quicksand: quicksand)
        first_improved = first.wins > first.neutral_wins ||
          (first.wins == first.neutral_wins && first.average_margin >= -0.005 && first.bid_accuracy_margin > 0.05)
        second_not_worse = second.wins >= second.neutral_wins && second.average_margin >= -0.02 &&
          second.bid_accuracy_margin >= -0.05
        improved = changed && first_improved && second_not_worse &&
          first.average_margin + second.average_margin > -0.01 &&
          first.incomplete_games == 0 && second.incomplete_games == 0 &&
          first_quality >= -0.03 && second_quality >= -0.05
        extended = nil
        # A large advantage on the discovery validation may be real even when
        # a tiny confirmation sample or a conservative quality guard rejects
        # it. Preserve such contenders and settle them on a substantially
        # larger fresh sample instead of discarding their weights immediately.
        if changed && !improved && first.incomplete_games == 0 &&
            first.wins > first.neutral_wins && first.average_margin >= 0.05
          extended_seeds = Array.new([validation_seeds.to_i * 5, 10].max) do |index|
            @seed + 110_000_000 + series_index * 100_000 + index * 149
          end
          extended = validation_arena.compare(
            candidate: candidate, opponent: champion, seeds: extended_seeds
          )
          extended_quality = extended.quality_advantage(quicksand: quicksand)
          overtrick_tolerance = quicksand ? 0.20 : 0.50
          improved = extended.incomplete_games == 0 &&
            extended.wins > extended.neutral_wins && extended.average_margin >= 0.02 &&
            extended_quality >= -0.12 &&
            extended.candidate_contract_rate >= extended.opponent_contract_rate - 0.08 &&
            extended.candidate_bid_error <= extended.opponent_bid_error + 0.25 &&
            extended.candidate_average_overtricks <=
              extended.opponent_average_overtricks + overtrick_tolerance
        end
        if improved
          @policy = candidate
          accepted_series += 1
          plateau = 0
        else
          @policy = champion
          plateau += 1
        end
        entry = {
          series: series_index,
          accepted: improved,
          plateau: plateau,
          generations: generation_history,
          validation: evaluation_summary(first),
          confirmation: evaluation_summary(second),
          extended_validation: extended == nil ? nil : evaluation_summary(extended)
        }
        history << entry
        yield(entry) if block_given?
      end
      CampaignReport.new(
        profile: @profile,
        policy: @policy,
        series: series_index,
        accepted_series: accepted_series,
        plateau: plateau,
        history: history
      )
    end

    private

    def evaluation_summary(evaluation)
      {
        games: evaluation.games,
        wins: evaluation.wins,
        neutral_wins: evaluation.neutral_wins,
        average_margin: evaluation.average_margin,
        average_actions: evaluation.average_actions,
        average_rounds: evaluation.average_rounds,
        bid_accuracy_margin: evaluation.bid_accuracy_margin,
        quality_advantage: evaluation.quality_advantage(
          quicksand: @scenarios.all? { |scenario| scenario.quicksand == true }
        ),
        candidate_bid_error: evaluation.candidate_bid_error,
        opponent_bid_error: evaluation.opponent_bid_error,
        candidate_bid_bias: evaluation.candidate_bid_bias,
        opponent_bid_bias: evaluation.opponent_bid_bias,
        candidate_contract_rate: evaluation.candidate_contract_rate,
        opponent_contract_rate: evaluation.opponent_contract_rate,
        candidate_average_overtricks: evaluation.candidate_average_overtricks,
        opponent_average_overtricks: evaluation.opponent_average_overtricks,
        candidate_average_shortfall: evaluation.candidate_average_shortfall,
        opponent_average_shortfall: evaluation.opponent_average_shortfall,
        average_table_bid_gap: evaluation.average_table_bid_gap,
        average_table_bid_deficit: evaluation.average_table_bid_deficit,
        incomplete_games: evaluation.incomplete_games
      }
    end
  end
end
