require_relative "../../tools/training/match_runner"
require "digest"
require "json"
require "time"
require_relative "../../lib/game_simulation"
require_relative "../../games/tysiac"

module TysiacAudit
  PLAY_ORACLE_THRESHOLD = 2_000.0
  INFORMATION_SET_SAMPLES = 64

  module_function

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end

  def action_key(action)
    action.to_h.keys.map(&:to_s).sort.map do |key|
      value = action[key] || action[key.to_sym]
      "#{key}=#{value}"
    end.join("|")
  end

  def stable_seed(*parts)
    Digest::SHA256.hexdigest(parts.map(&:to_s).join("\0"))[0, 15].to_i(16)
  end

  class Collector
    attr_reader :decisions, :issues, :matches, :rounds

    def initialize
      @decisions = []
      @issues = []
      @matches = []
      @rounds = []
      @snapshots = []
    end

    def record_decision(entry, snapshot: nil)
      @decisions << entry
      @snapshots << [entry, snapshot] if snapshot != nil
    end

    def record_issue(issue)
      @issues << issue
    end

    def record_match(entry)
      @matches << entry
    end

    def record_round(entry)
      @rounds << entry
    end

    def deep_check!(limit: 80, samples: INFORMATION_SET_SAMPLES)
      candidates = @snapshots.sort_by do |entry, _snapshot|
        -entry.fetch("oracle_regret", 0.0).to_f
      end.first(limit.to_i)
      candidates.each do |entry, snapshot|
        scores = information_set_scores(snapshot, samples: samples)
        next if scores.empty?

        selected = entry["action_key"]
        best_key, best_score = scores.max_by { |_key, score| score }
        selected_score = scores.fetch(selected, -Float::INFINITY)
        entry["information_set_best"] = best_key
        entry["information_set_regret"] = best_score - selected_score
        entry["information_set_scores"] = scores.sort_by { |_key, score| -score }.first(4).to_h
        next if best_key == selected || entry["information_set_regret"] < 250.0

        record_issue({
          "kind" => "confirmed_play_regret",
          "match" => entry["match"],
          "round" => entry["round"],
          "actor" => entry["actor"],
          "selected" => selected,
          "recommended" => best_key,
          "oracle_regret" => entry["oracle_regret"],
          "information_set_regret" => entry["information_set_regret"],
          "scores" => entry["information_set_scores"]
        })
      end
    end

    def summary
      finished = @matches.count { |match| match["reason"] == "finished" }
      failures = @rounds.count { |round| !round["contract_made"] && !round["surrendered"] }
      taker_rounds = @rounds.length
      margins = @rounds.map { |round| round["contract_margin"].to_i }
      issue_counts = @issues.each_with_object(Hash.new(0)) do |issue, result|
        result[issue.fetch("kind")] += 1
      end
      {
        "matches" => @matches.length,
        "finished_matches" => finished,
        "rounds" => taker_rounds,
        "contract_failures" => failures,
        "contract_failure_rate" => taker_rounds.zero? ? 0.0 : failures.to_f / taker_rounds,
        "average_contract_margin" => margins.empty? ? 0.0 : margins.sum.to_f / margins.length,
        "decisions" => @decisions.length,
        "play_decisions" => @decisions.count { |decision| decision["phase"] == "playing" },
        "issues" => @issues.length,
        "issue_counts" => issue_counts.sort.to_h,
        "wins_by_seat" => @matches.each_with_object(Hash.new(0)) do |match, result|
          result[match["winner_seat"].to_s] += 1 if match["winner_seat"] != nil
        end.sort.to_h,
        "average_actions" => @matches.empty? ? 0.0 : @matches.sum { |match| match["actions"].to_i }.to_f / @matches.length,
        "average_seconds" => @matches.empty? ? 0.0 : @matches.sum { |match| match["seconds"].to_f }.to_f / @matches.length
      }
    end

    def report
      {
        "format" => "tysiac-audit-v1",
        "generated_at" => Time.now.utc.iso8601,
        "summary" => summary,
        "matches" => @matches,
        "rounds" => @rounds,
        "issues" => @issues.sort_by do |issue|
          [-issue.fetch("information_set_regret", issue.fetch("oracle_regret", 0.0)).to_f,
            issue.fetch("match", 0).to_i,
            issue.fetch("round", 0).to_i]
        end,
        "decisions" => @decisions
      }
    end

    private

    def information_set_scores(snapshot, samples:)
      game = snapshot.fetch(:game)
      replay = snapshot.fetch(:replay)
      actor = snapshot.fetch(:actor)
      actions = snapshot.fetch(:actions)
      planner = TysiacPlanning::Planner.new(
        game,
        replay,
        actor,
        GameRoomRandom::SeededSource.new(snapshot.fetch(:audit_seed))
      )
      worlds = planner.send(:sampled_worlds, samples.to_i)
      return {} if worlds.empty?

      actions.each_with_object({}) do |action, result|
        utilities = worlds.filter_map do |world|
          simulated = planner.send(:clone_world, world)
          mode, card = planner.send(:parse_action_card, action)
          next if !planner.send(:play_card, simulated, actor, mode, card)

          planner.send(:finish_round, simulated)
          planner.send(:evaluate, simulated, actor)
        end
        next if utilities.empty?

        ordered = utilities.sort
        mean = utilities.sum / utilities.length.to_f
        lower_quartile = ordered[((ordered.length - 1) * 0.25).floor]
        heuristic = game.bot_action_score(replay, actor, action).to_f
        result[TysiacAudit.action_key(action)] = mean + lower_quartile * 0.18 + heuristic * 0.03
      end
    end
  end

  class TracingStrategy
    MAX_ORACLE_CHECKS_PER_SEAT = 24

    def initialize(strategy:, game:, collector:, match_index:, match_seed:, seat:)
      @strategy = strategy
      @game = game
      @collector = collector
      @match_index = match_index.to_i
      @match_seed = match_seed.to_i
      @seat = seat.to_i
      @decision_index = 0
      @oracle_checks = 0
    end

    def choose(actions:, actor:, random_source:, game:, replay:, context: nil, simulation: nil, **extra)
      @decision_index += 1
      decision_seed = TysiacAudit.stable_seed(@match_seed, @seat, @decision_index, actor)
      strategy_random = GameRoomRandom::SeededSource.new(decision_seed)
      arguments = {
        actions: actions,
        observation: game.bot_observation(replay, actor),
        actor: actor,
        random_source: strategy_random,
        game: game,
        replay: replay,
        context: context,
        simulation: simulation
      }.merge(extra)
      chosen = GameRoomBots.choose(@strategy, arguments)
      audit_decision(actions.to_a, actor.to_s, replay, chosen, decision_seed)
      chosen
    end

    private

    def audit_decision(actions, actor, replay, chosen, decision_seed)
      return if chosen == nil

      state = replay.state
      entry = {
        "match" => @match_index,
        "seed" => @match_seed,
        "seat" => @seat + 1,
        "decision" => @decision_index,
        "round" => state[:round].to_i,
        "phase" => state[:phase].to_s,
        "actor" => actor,
        "action_key" => TysiacAudit.action_key(chosen),
        "legal_action_count" => actions.length,
        "contract" => state[:contract],
        "taker" => state[:taker],
        "scores" => TysiacAudit.deep_copy(state[:scores]),
        "barrels" => TysiacAudit.deep_copy(state[:barrels]),
        "passed" => TysiacAudit.deep_copy(state[:passed]),
        "current_bid" => state[:current_bid],
        "current_bidder" => state[:current_bidder],
        "round_points" => TysiacAudit.deep_copy(state[:round_points]),
        "trump" => state[:trump],
        "current_trick" => TysiacAudit.deep_copy(state[:current_trick]),
        "trick_number" => state[:trick_number].to_i,
        "trick_size" => state[:current_trick].to_a.length
      }
      player = state[:players].find { |candidate| GameRoomParticipants.same?(candidate, actor) }
      if player != nil
        entry["hand"] = state[:hands].fetch(player, []).dup
        entry["estimate"] = @game.send(:bot_contract_estimate, state, player).round(3)
      end
      add_passing_checks(entry, state, actor, chosen)
      snapshot = add_play_checks(entry, state, replay, actor, actions, chosen, decision_seed)
      @collector.record_decision(entry, snapshot: snapshot)
    end

    def add_passing_checks(entry, state, actor, chosen)
      return if state[:phase] != :passing || chosen["action"].to_s != "select"

      card = chosen["card"].to_s
      recipients = @game.send(:pass_recipients, state)
      recipient = recipients[state[:pass_index].to_i]
      return if recipient == nil

      rank = card[0]
      suit = card[1]
      counterpart = rank == "K" ? "Q#{suit}" : rank == "Q" ? "K#{suit}" : nil
      player = state[:players].find { |candidate| GameRoomParticipants.same?(candidate, actor) }
      hand = state[:hands].fetch(player, [])
      if counterpart != nil && state[:hands].fetch(recipient, []).include?(counterpart)
        @collector.record_issue({
          "kind" => "pass_completed_opponent_marriage",
          "match" => @match_index,
          "round" => state[:round].to_i,
          "actor" => actor,
          "recipient" => recipient,
          "card" => card,
          "counterpart" => counterpart
        })
      end
      if counterpart != nil && hand.include?(counterpart)
        @collector.record_issue({
          "kind" => "pass_broke_own_marriage",
          "match" => @match_index,
          "round" => state[:round].to_i,
          "actor" => actor,
          "recipient" => recipient,
          "card" => card,
          "counterpart" => counterpart
        })
      end
      entry["pass_recipient"] = recipient
      entry["passed_card"] = card
    end

    def add_play_checks(entry, state, replay, actor, actions, chosen, decision_seed)
      return nil if state[:phase] != :playing

      heuristic_scores = actions.to_h do |action|
        [TysiacAudit.action_key(action), @game.bot_action_score(replay, actor, action).to_f]
      end
      heuristic_best = heuristic_scores.max_by { |_key, score| score }&.first
      entry["heuristic_best"] = heuristic_best
      return nil if !oracle_worthy?(state, entry, heuristic_best)

      @oracle_checks += 1

      scores = full_information_scores(replay, actor, actions, decision_seed)
      selected_key = entry["action_key"]
      best_key, best_score = scores.max_by { |_key, score| score }
      selected_score = scores.fetch(selected_key, -Float::INFINITY)
      regret = best_score - selected_score
      entry["oracle_best"] = best_key
      entry["oracle_regret"] = regret.round(3)
      entry["oracle_scores"] = scores.sort_by { |_key, score| -score }.first(4).to_h

      mode, _card = chosen["card"].to_s.split("|", 2)
      if state[:current_trick].to_a.empty? && state[:trick_number].to_i > 0 && mode != "marriage"
        hand = entry.fetch("hand", [])
        available = @game.class::SUITS.select do |suit|
          hand.include?("K#{suit}") && hand.include?("Q#{suit}")
        end
        if !available.empty?
          @collector.record_issue({
            "kind" => "undeclared_available_marriage",
            "match" => @match_index,
            "round" => state[:round].to_i,
            "actor" => actor,
            "suits" => available,
            "selected" => selected_key
          })
        end
      end
      return nil if best_key == selected_key || regret < PLAY_ORACLE_THRESHOLD

      {
        game: @game,
        replay: TysiacAudit.deep_copy(replay),
        actor: actor,
        actions: TysiacAudit.deep_copy(actions),
        audit_seed: TysiacAudit.stable_seed(decision_seed, "information-set")
      }
    end

    def oracle_worthy?(state, entry, heuristic_best)
      return false if @oracle_checks >= MAX_ORACLE_CHECKS_PER_SEAT
      return false if entry["legal_action_count"].to_i <= 1

      hand = entry.fetch("hand", [])
      marriage_available = state[:current_trick].to_a.empty? && state[:trick_number].to_i > 0 &&
        @game.class::SUITS.any? do |suit|
          hand.include?("K#{suit}") && hand.include?("Q#{suit}")
        end
      trick_points = state[:current_trick].to_a.sum do |play|
        @game.class::CARD_POINTS.fetch(play[:card].to_s[0], 0)
      end
      taker = state[:taker]
      need = if taker == nil
        0
      else
        [state[:contract].to_i - state[:round_points].fetch(taker, 0).to_i, 0].max
      end
      selected_differs = heuristic_best != nil && heuristic_best != entry["action_key"]
      state[:current_trick].to_a.empty? ||
        state[:current_trick].to_a.length == state[:players].length - 1 ||
        marriage_available || selected_differs || trick_points >= 15 || need <= 35
    end

    def full_information_scores(replay, actor, actions, decision_seed)
      planner = TysiacPlanning::Planner.new(
        @game,
        replay,
        actor,
        GameRoomRandom::SeededSource.new(TysiacAudit.stable_seed(decision_seed, "oracle"))
      )
      hands = replay.state[:hands].each_with_object({}) do |(player, hand), result|
        result[player] = hand.dup
      end
      world = planner.send(:world_from_state, hands: hands)
      actions.each_with_object({}) do |action, result|
        simulated = planner.send(:clone_world, world)
        mode, card = planner.send(:parse_action_card, action)
        next if !planner.send(:play_card, simulated, actor, mode, card)

        planner.send(:finish_round, simulated)
        result[TysiacAudit.action_key(action)] = planner.send(:evaluate, simulated, actor)
      end
    end
  end

  class Benchmark
    def initialize(matches:, seed:, score_limit: 1_000, deep_checks: 80,
        information_set_samples: INFORMATION_SET_SAMPLES, strategy: nil)
      @match_count = [matches.to_i, 1].max
      @seed = seed.to_i
      @score_limit = score_limit.to_i
      @deep_checks = [deep_checks.to_i, 0].max
      @information_set_samples = [information_set_samples.to_i, 1].max
      @game = GameRoomGames::Tysiac.new
      @strategy = strategy || @game.bot_strategy
      @players = GameRoomParticipants.bots_for(1, 3)
      @collector = Collector.new
    end

    attr_reader :collector

    def run
      @match_count.times do |offset|
        match_index = offset + 1
        match_seed = @seed + offset
        strategies = @players.each_with_index.to_h do |player, seat|
          [player, TracingStrategy.new(
            strategy: @strategy,
            game: @game,
            collector: @collector,
            match_index: match_index,
            match_seed: match_seed,
            seat: seat
          )]
        end
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = GameRoomSimulation::MatchRunner.new(
          game: @game,
          players: @players,
          options: { "score_limit" => @score_limit },
          strategies: strategies,
          max_actions: 12_000
        ).run(seed: match_seed)
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
        winner_seat = @players.index do |player|
          result.winner != nil && GameRoomParticipants.same?(player, result.winner)
        end
        @collector.record_match({
          "match" => match_index,
          "seed" => match_seed,
          "reason" => result.reason.to_s,
          "winner" => result.winner,
          "winner_seat" => winner_seat == nil ? nil : winner_seat + 1,
          "actions" => result.actions,
          "seconds" => elapsed.round(3),
          "scores" => result.final_state[:scores]
        })
        extract_rounds(result, match_index, match_seed)
        yield(match_index, @match_count, elapsed, result) if block_given?
      end
      @collector.deep_check!(limit: @deep_checks, samples: @information_set_samples) if @deep_checks > 0
      @collector
    end

    private

    def extract_rounds(result, match_index, match_seed)
      events = result.events
      deal_indexes = events.each_index.select { |index| events[index]["action"].to_s == "deal" }
      session = {
        "__id" => 1,
        "table_id" => 1,
        "game" => @game.id,
        "options" => JSON.generate(@game.normalize_options("score_limit" => @score_limit)),
        "__players" => @players
      }
      repository = GameRoomSimulation::Repository.new(@players)
      deal_indexes.each_with_index do |start_index, round_offset|
        end_index = (deal_indexes[round_offset + 1] || events.length) - 1
        next if end_index < start_index

        replay = @game.replay(session, events[0..end_index], repository)
        state = replay.state
        next if state[:round].to_i != round_offset + 1
        next if ![:round_complete, :finished].include?(state[:phase])

        taker = state[:taker]
        points = state[:round_points].fetch(taker, 0).to_i
        contract = state[:contract].to_i
        surrendered = events[start_index..end_index].any? { |event| event["action"].to_s == "surrender" }
        entry = {
          "match" => match_index,
          "seed" => match_seed,
          "round" => state[:round].to_i,
          "taker" => taker,
          "contract" => contract,
          "points" => points,
          "contract_margin" => points - contract,
          "contract_made" => !surrendered && points >= contract,
          "surrendered" => surrendered,
          "round_points" => state[:round_points],
          "scores" => state[:scores]
        }
        @collector.record_round(entry)
        if !surrendered && points < contract
          @collector.record_issue({
            "kind" => "failed_contract",
            "match" => match_index,
            "round" => state[:round].to_i,
            "actor" => taker,
            "contract" => contract,
            "points" => points,
            "shortfall" => contract - points
          })
        end
      end
    end
  end

end
