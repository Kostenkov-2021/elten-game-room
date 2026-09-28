require "json"
require_relative "game_bots"
require_relative "game_simulation"
require_relative "spades_trained_profiles"

module SpadesLearning
  PROFILE_KEYS = %w[
    standard_individual
    standard_team
    quicksand_individual
    quicksand_team
  ].freeze
  ARRANGEMENT_PROFILES = {
    "standard_individual_p3" => ["standard_individual", 3, 0],
    "standard_individual_p4" => ["standard_individual", 4, 0],
    "standard_individual_p5" => ["standard_individual", 5, 0],
    "standard_individual_p6" => ["standard_individual", 6, 0],
    "standard_team_p4_t2" => ["standard_team", 4, 2],
    "standard_team_p6_t2" => ["standard_team", 6, 2],
    "standard_team_p6_t3" => ["standard_team", 6, 3],
    "quicksand_individual_p3" => ["quicksand_individual", 3, 0],
    "quicksand_individual_p4" => ["quicksand_individual", 4, 0],
    "quicksand_individual_p5" => ["quicksand_individual", 5, 0],
    "quicksand_individual_p6" => ["quicksand_individual", 6, 0],
    "quicksand_team_p4_t2" => ["quicksand_team", 4, 2],
    "quicksand_team_p6_t2" => ["quicksand_team", 6, 2],
    "quicksand_team_p6_t3" => ["quicksand_team", 6, 3]
  }.freeze

  class Policy
    DEFAULT_WEIGHTS = {
      "bidding" => {
        "distance" => 9.0,
        "overbid" => 2.5,
        "underbid" => 1.0,
        "nil_safety" => 1.5,
        "contract_size" => 0.1
      },
      "playing" => {
        "low_card" => 2.0,
        "trump_cost" => 1.4,
        "last_win_needed" => 7.0,
        "last_win_unneeded" => -3.5,
        "nil_win" => -12.0,
        "protect_partner" => 4.5,
        "overtake_partner" => -6.0,
        "discard_high" => 2.5,
        "lead_spade" => -0.8,
        "win_before_last" => 1.0,
        "bag_risk_win" => -2.5
      }
    }.freeze

    # Immutable build 48 champion. It remains the benchmark after richer
    # policies become the client default.
    BUILD_48_WEIGHTS = {
      "bidding" => {
        "distance" => 10.811094021956706,
        "overbid" => 1.8122476726104408,
        "underbid" => 3.0292551407796373,
        "nil_safety" => 0.9016286200718441,
        "contract_size" => 2.0517528823222038
      },
      "playing" => {
        "low_card" => 2.2675504506810347,
        "trump_cost" => 0.14182372266177085,
        "last_win_needed" => 6.819059301528677,
        "last_win_unneeded" => -4.359867452628425,
        "nil_win" => -13.272355359224036,
        "protect_partner" => 4.252015443714496,
        "overtake_partner" => -6.278015478728513,
        "discard_high" => 2.612981219082447,
        "lead_spade" => -2.729486981344627,
        "win_before_last" => 1.003043386830477,
        "bag_risk_win" => -2.6594902212765263
      }
    }.freeze
    TRAINED_WEIGHTS = BUILD_48_WEIGHTS

    STRATEGIC_WEIGHTS = {
      "bidding" => BUILD_48_WEIGHTS["bidding"].merge(
        "certain_tricks" => 3.0,
        "nil_risk" => -7.0,
        "void_value" => 0.8,
        "trump_length" => 0.7,
        "team_bid_balance" => 2.0,
        "table_bid_balance" => 0.0,
        "table_underbid_pressure" => 0.0,
        "table_overbid_pressure" => 0.0,
        "last_bid_table_balance" => 0.0,
        "trailing_aggression" => 1.8,
        "leading_caution" => -0.8,
        "bag_pressure_bid" => 1.6,
        "quicksand_precision" => 3.0
      ),
      "playing" => BUILD_48_WEIGHTS["playing"].merge(
        "cheapest_winner" => 4.0,
        "cash_contract_run" => 5.0,
        "highest_safe_loser" => 1.8,
        "needed_win_probability" => 0.0,
        "unneeded_win_probability" => 0.0,
        "unneeded_high_release" => 0.0,
        "early_avoid_win_probability" => -3.0,
        "early_avoid_high_release" => 1.5,
        "early_avoid_safe_loser" => 1.0,
        "known_winner_needed" => 3.0,
        "waste_known_winner" => -2.5,
        "higher_cards_unseen" => -1.2,
        "lead_short_suit" => 0.8,
        "lead_into_opponent_void" => -1.5,
        "lead_into_partner_void" => 1.2,
        "draw_trump" => 1.0,
        "partner_nil_cover" => 12.0,
        "partner_nil_safe_lead" => 3.0,
        "partner_nil_lead_control" => 18.0,
        "partner_nil_control" => 18.0,
        "partner_nil_distant_control" => 18.0,
        "opponent_nil_feed" => 9.0,
        "opponent_nil_pressure" => 2.0,
        "deny_opponent_contract" => 6.0,
        "force_opponent_set" => 12.0,
        "tight_table_denial" => 3.0,
        "trailing_contract_win" => 2.0,
        "leading_avoid_extra" => -1.0,
        "quicksand_extra_win" => -8.0,
        "quicksand_needed_win" => 5.0,
        "bag_penalty_imminent" => -6.0,
        "preserve_trump" => 1.0
      )
    }.freeze

    PROFILE_OVERRIDES = {
      "standard_individual" => {
        "playing" => {
          "protect_partner" => 0.0,
          "overtake_partner" => 0.0,
          "partner_nil_cover" => 0.0,
          "partner_nil_safe_lead" => 0.0,
          "lead_into_partner_void" => 0.0,
          "needed_win_probability" => 4.0,
          "unneeded_win_probability" => -8.0,
          "unneeded_high_release" => 4.0,
          "early_avoid_win_probability" => -1.5,
          "early_avoid_high_release" => 0.75,
          "early_avoid_safe_loser" => 0.5,
          "deny_opponent_contract" => 3.0,
          "force_opponent_set" => 9.0,
          "tight_table_denial" => 1.5
        }
      },
      "standard_team" => {
        "playing" => {
          "protect_partner" => 5.0,
          "partner_nil_cover" => 14.0,
          "partner_nil_safe_lead" => 4.0
        }
      },
      "quicksand_individual" => {
        "bidding" => { "bag_pressure_bid" => 0.0, "quicksand_precision" => 5.0 },
        "playing" => {
          "protect_partner" => 0.0,
          "overtake_partner" => 0.0,
          "partner_nil_cover" => 0.0,
          "partner_nil_safe_lead" => 0.0,
          "lead_into_partner_void" => 0.0,
          "bag_risk_win" => 0.0,
          "bag_penalty_imminent" => 0.0,
          "quicksand_extra_win" => -12.0,
          "needed_win_probability" => 4.0,
          "unneeded_win_probability" => -8.0,
          "unneeded_high_release" => 4.0
        }
      },
      "quicksand_team" => {
        "bidding" => { "bag_pressure_bid" => 0.0, "quicksand_precision" => 5.0 },
        "playing" => {
          "protect_partner" => 5.0,
          "partner_nil_cover" => 14.0,
          "partner_nil_safe_lead" => 4.0,
          "bag_risk_win" => 0.0,
          "bag_penalty_imminent" => 0.0,
          "quicksand_extra_win" => -12.0,
          "quicksand_needed_win" => 7.0
        }
      }
    }.freeze
    INDIVIDUAL_INACTIVE_FEATURES = %w[
      protect_partner overtake_partner lead_into_partner_void
      partner_nil_cover partner_nil_safe_lead partner_nil_lead_control partner_nil_control
      partner_nil_distant_control
    ].freeze

    attr_reader :weights

    def self.default
      new(BUILD_48_WEIGHTS)
    end

    def self.strategic(profile)
      weights = deep_copy(STRATEGIC_WEIGHTS)
      PROFILE_OVERRIDES.fetch(profile.to_s, {}).each do |phase, entries|
        weights[phase] ||= {}
        weights[phase].merge!(entries)
      end
      new(weights)
    end

    # Older checkpoints may predate newly introduced strategic features. A
    # missing weight must not silently disable the feature forever, because
    # mutation can only tune weights already present in a policy. Start with
    # the complete strategic policy and overlay every value learned by the
    # checkpoint.
    def self.complete(profile, weights)
      values = strategic(profile).to_h
      source = weights.to_h
      source.each do |phase, entries|
        values[phase.to_s] ||= {}
        entries.to_h.each { |name, weight| values[phase.to_s][name.to_s] = weight.to_f }
      end
      if profile.to_s.end_with?("individual")
        INDIVIDUAL_INACTIVE_FEATURES.each { |name| values["playing"][name] = 0.0 }
      end
      new(values)
    end

    def self.deep_copy(value)
      Marshal.load(Marshal.dump(value))
    end

    def initialize(weights = DEFAULT_WEIGHTS)
      @weights = normalize(weights)
    end

    def score(phase, features)
      phase_weights = @weights.fetch(phase.to_s, {})
      features.to_h.sum do |name, value|
        phase_weights.fetch(name.to_s, 0.0) * value.to_f
      end
    end

    def mutated(random, scale: 0.5)
      values = to_h
      values.each_value do |phase|
        phase.each_key do |name|
          next if random.rand >= 0.35

          phase[name] = [[phase[name] + (random.rand * 2.0 - 1.0) * scale.to_f, -20.0].max, 20.0].min
        end
      end
      self.class.new(values)
    end

    def to_h
      self.class.deep_copy(@weights)
    end

    def to_json(*arguments)
      JSON.generate(@weights, *arguments)
    end

    def self.from_json(value)
      new(JSON.parse(value.to_s))
    end

    private

    def normalize(value)
      value.to_h.each_with_object({}) do |(phase, weights), result|
        result[phase.to_s] = weights.to_h.each_with_object({}) do |(name, weight), entries|
          entries[name.to_s] = weight.to_f
        end
      end
    end
  end

  class PolicySet
    attr_reader :profiles

    def self.strategic
      new(PROFILE_KEYS.each_with_object({}) do |profile, result|
        result[profile] = Policy.strategic(profile)
      end)
    end

    def self.build_48
      new(PROFILE_KEYS.each_with_object({}) do |profile, result|
        result[profile] = Policy.default
      end, complete: false)
    end

    # Replaced with accepted campaign checkpoints after offline training.
    def self.default
      new(TRAINED_PROFILE_WEIGHTS)
    end

    def initialize(profiles, complete: true)
      @profiles = PROFILE_KEYS.each_with_object({}) do |profile, result|
        value = profiles.fetch(profile) { profiles.fetch(profile.to_sym, Policy.strategic(profile)) }
        result[profile] = policy_from(profile, value, complete)
      end
      profiles.each do |profile, value|
        next if @profiles.key?(profile.to_s)

        key = profile.to_s
        base = self.class.base_profile_key(key)
        if complete && @profiles.key?(base)
          inherited = @profiles.fetch(base).to_h
          source = value.is_a?(Policy) ? value.to_h : value.to_h
          source.each do |phase, entries|
            inherited[phase.to_s] ||= {}
            entries.to_h.each { |name, weight| inherited[phase.to_s][name.to_s] = weight.to_f }
          end
          @profiles[key] = Policy.complete(base, inherited)
        else
          @profiles[key] = policy_from(base, value, complete)
        end
      end
    end

    def for_options(options)
      @profiles.fetch(self.class.profile_key(options))
    end

    def for_state(state)
      specific = self.class.arrangement_profile_key(state[:options], state[:players].length)
      @profiles[specific] || for_options(state[:options])
    end

    def to_h
      @profiles.transform_values(&:to_h)
    end

    def self.profile_key(options)
      values = options || {}
      variant = values["quicksand"] == true || values[:quicksand] == true ? "quicksand" : "standard"
      team_size = values["team_size"] || values[:team_size]
      arrangement = team_size.to_i > 0 ? "team" : "individual"
      "#{variant}_#{arrangement}"
    end

    def self.arrangement_profile_key(options, player_count)
      base = profile_key(options)
      team_size = (options["team_size"] || options[:team_size]).to_i
      team_size > 0 ? "#{base}_p#{player_count}_t#{team_size}" : "#{base}_p#{player_count}"
    end

    def self.base_profile_key(profile)
      key = profile.to_s
      match = /\A(.+)_p\d+(?:_t\d+)?\z/.match(key)
      match == nil ? key : match[1]
    end

    private

    def policy_from(profile, value, complete)
      return value if value.is_a?(Policy) && !complete
      return Policy.new(value) if !complete

      Policy.complete(profile, value)
    end
  end

  class Strategy
    include GameRoomBots::ReplayOnlyStrategy

    attr_reader :policy, :policies

    def initialize(policy: nil, policies: nil, round_planning: true)
      @policy = policy
      @policies = policies || (policy == nil ? PolicySet.default : nil)
      @round_planning = round_planning == true
    end

    def choose(actions:, actor:, random_source:, game:, replay:, **_extra)
      choices = actions.to_a
      return nil if choices.empty?

      selected_policy = @policy || @policies.for_state(replay.state)
      phase = replay.state[:phase].to_s
      if phase == "bidding"
        allowed = game.send(:undominated_bot_bids, replay.state, actor, choices.map { |action| action["bid"].to_i })
        choices = choices.select { |action| allowed.include?(action["bid"].to_i) }
      end
      context = if game.respond_to?(:bot_decision_context)
        game.bot_decision_context(replay, actor, plan_round: @round_planning)
      end
      plan = context && context[:round_plan]
      if plan && plan[:exact_decision] && !plan[:raw_scores].empty?
        best_value = plan[:raw_scores].values.max
        choices = choices.select { |action| plan[:raw_scores][action["card"]] == best_value }
      end
      scored = choices.map do |action|
        features = game.bot_action_features(replay, actor, action, context: context)
        shared_adjustment = game.bot_policy_score_adjustment(replay.state, actor, action, context)
        planning_adjustment = if game.respond_to?(:bot_planning_score_adjustment)
          game.bot_planning_score_adjustment(replay.state, actor, action, context)
        else
          0.0
        end
        [action, selected_policy.score(phase, features) + shared_adjustment + planning_adjustment]
      end
      best = scored.map(&:last).max
      GameRoomBots.random_choice(
        scored.select { |_action, score| score == best }.map(&:first),
        random_source
      )
    end
  end

end
