require_relative '../../lib/game_room_localization'

module GameRoomGames
  using GameRoomLocalization::Translations
  class Spades
    module PlayEvaluation
      private

      # A completed contract is normally followed by overtrick avoidance. That
      # priority must yield when an opponent can end the whole match by making the
      # contract still in progress. Reward a reliable trick only while it can
      # actually deny that opponent; do not overtake an ally or another opponent
      # who is already taking the trick away from the match threat.
      def bot_match_defense_score_adjustment(state, actor, action, context)
        return 0.0 if !context.is_a?(Hash)

        threats = bot_match_contract_threats(state, actor)
        return 0.0 if threats.empty?

        leader = if state[:current_trick].to_a.empty?
          nil
        else
          trick_winner(state[:current_trick])
        end
        if leader != nil && threats.none? { |threat| bot_state_allied?(state, threat[:player], leader) }
          return 0.0
        end

        card = action["card"].to_s
        probability = context.fetch(:win_probabilities, {}).fetch(card, 0.0).to_f
        return 0.0 if probability <= 0.0

        urgency = threats.map { |threat| threat[:urgency].to_f }.max.to_f
        MATCH_DEFENSE_TRICK_PRIORITY * probability * urgency
      end

      def bot_match_contract_threats(state, actor)
        remaining_tricks = hand_for(state, actor).to_a.length
        return [] if remaining_tricks <= 0

        limit = [state[:options]["score_limit"].to_i, 1].max
        actor_unit = bot_score_context(state, actor)[:unit].to_s
        seen_units = {}
        state[:players].each_with_object([]) do |player, result|
          next if bot_state_allied?(state, actor, player)

          unit = bot_score_context(state, player)[:unit].to_s
          next if seen_units[unit]

          seen_units[unit] = true
          contract = bot_regular_contract(state, player)
          next if contract[:bid].to_i <= 0 || contract[:need].to_i <= 0
          next if contract[:need].to_i > remaining_tricks

          projected_score = bot_projected_contract_score(state, unit, contract)
          next if projected_score < limit
          next if projected_score <= state[:scores].fetch(actor_unit, 0).to_i

          result << {
            player: player_key(state, player),
            unit: unit,
            projected_score: projected_score,
            urgency: 0.75 + 0.25 * contract[:need].to_f / remaining_tricks
          }
        end
      end

      def bot_projected_contract_score(state, unit, contract)
        tricks = state[:tricks].dup
        scoring = Scoring.new(state[:players], state[:options])
        members = scoring.members_for(unit)
        regular = members.reject { |player| state[:bids].fetch(player, -1).to_i == 0 }
        recipient = regular.first
        if recipient != nil
          tricks[recipient] = tricks.fetch(recipient, 0).to_i + contract[:need].to_i
        end
        scoring.apply(
          bids: state[:bids],
          tricks: tricks,
          scores: state[:scores]
        ).scores.fetch(unit, state[:scores].fetch(unit, 0)).to_i
      end

      # When playing last, the trick winner is certain. If our contract is
      # already complete and an opponent has also completed theirs, deliberately
      # leaving that opponent an overtrick is useful at eight bags and especially
      # at nine, where the next bag causes the standard hundred-point penalty.
      # Earlier seats receive no correction because later cards may change the
      # winner; Quicksand has no persistent bags at all.
      def bot_opponent_bag_pressure_score_adjustment(state, actor, action)
        return 0.0 if state[:options]["quicksand"] == true
        return 0.0 if state[:current_trick].to_a.length != state[:players].to_a.length - 1
        return 0.0 if bot_contract_remaining(state, actor) > 0

        actor_key = player_key(state, actor)
        card = action["card"].to_s
        return 0.0 if actor_key == nil || card.empty?

        assignment = team_assignment(state[:options], players: state[:players])
        if assignment != nil
          active_partner_nil = assignment.teammates_for(actor_key).any? do |player|
            !same_user?(player, actor_key) &&
              state[:bids].fetch(player, -1).to_i == 0 &&
              state[:tricks].fetch(player, 0).to_i == 0
          end
          return 0.0 if active_partner_nil
        end

        completed_trick = state[:current_trick] + [{ player: actor_key, card: card }]
        winner = trick_winner(completed_trick)
        return 0.0 if winner == nil || bot_state_allied?(state, actor_key, winner)
        return 0.0 if state[:bids].fetch(player_key(state, winner), -1).to_i == 0
        return 0.0 if bot_regular_contract(state, winner)[:need] > 0

        bags = bot_score_context(state, winner)[:bags].to_i
        return 0.0 if bags < 8

        bags >= 9 ? 8.0 : 3.0
      end

      # Several cards can have exactly the same immediate result when the bot is
      # last to play. While a regular contract is still outstanding, prefer the
      # winner that preserves the greatest number of mathematically certain top
      # spades. Once every remaining required trick is still covered, prefer the
      # alternative that leaves the smallest surplus of those controls. This
      # prevents wasting an ace that is needed later without forcing a completed
      # contract to retain an avoidable future overtrick.
      def bot_last_seat_winner_conservation_score_adjustment(state, actor, action)
        players = state[:players].to_a
        return 0.0 if state[:current_trick].to_a.length != players.length - 1

        actor_key = player_key(state, actor)
        return 0.0 if actor_key == nil || state[:bids].fetch(actor_key, -1).to_i == 0

        card = action["card"].to_s
        return 0.0 if card.empty?

        winning_cards = legal_cards(state, actor).select do |candidate|
          completed = state[:current_trick] + [{ player: actor_key, card: candidate }]
          same_user?(trick_winner(completed), actor_key)
        end
        return 0.0 if winning_cards.length < 2 || !winning_cards.include?(card)

        need_after = [bot_contract_remaining(state, actor) - 1, 0].max
        candidates = winning_cards.map do |candidate|
          [candidate, bot_guaranteed_top_spades_after(state, actor_key, candidate)]
        end
        safe = candidates.select { |_candidate, controls| controls >= need_after }
        preferred = if !safe.empty?
          minimum_surplus = safe.map { |_candidate, controls| controls - need_after }.min
          exact = safe.select { |_candidate, controls| controls - need_after == minimum_surplus }
          if need_after > 0
            exact.min_by { |candidate, _controls| bot_card_cost(state, candidate) }
          else
            exact.max_by { |candidate, _controls| bot_card_cost(state, candidate) }
          end
        else
          maximum_controls = candidates.map(&:last).max
          candidates.select { |_candidate, controls| controls == maximum_controls }
            .min_by { |candidate, _controls| bot_card_cost(state, candidate) }
        end

        # Protecting an otherwise uncovered required trick is a hard tactical
        # constraint. When every candidate already keeps the contract secure,
        # surplus control is only a modest bag-avoidance preference: the round
        # planner may override it to break an opponent's contract.
        strength = safe.length == candidates.length ? 3.0 : 18.0
        preferred.first == card ? strength : -strength
      end

      # Top spades form a conservative, public-information proof of future tricks:
      # their ownership distribution is irrelevant until the first outstanding
      # spade not held by the actor is reached. Reading the union of remaining
      # hands reveals no private location and therefore keeps fair bots fair.
      def bot_guaranteed_top_spades_after(state, actor, played_card)
        actor_hand = hand_for(state, actor).to_a.dup
        index = actor_hand.index(played_card)
        actor_hand.delete_at(index) if index != nil

        remaining = state[:hands].to_h.values.flat_map(&:to_a)
        index = remaining.index(played_card)
        remaining.delete_at(index) if index != nil
        remaining.select { |candidate| card_suit(candidate) == "S" }
          .sort_by { |candidate| -RANKS.index(card_rank(candidate)).to_i }
          .take_while { |candidate| actor_hand.include?(candidate) }
          .length
      end

      # Do not throw away a newly promoted side-suit winner underneath a card
      # which has already won the current trick. This is provable from public
      # cards alone in cases such as KC under AC, so the protection is available
      # to fair bots as well as to the perfect-information challenge mode.
      def bot_future_control_conservation_score_adjustment(state, actor, action, context)
        card = action["card"].to_s
        return 0.0 if !bot_future_control_discard?(state, actor, card, context)

        -FUTURE_CONTROL_DISCARD_PENALTY
      end

      def bot_future_control_discard?(state, actor, card, context = nil)
        trick = state[:current_trick].to_a
        return false if trick.empty? || bot_contract_remaining(state, actor) <= 0

        actor_key = player_key(state, actor)
        return false if actor_key == nil || state[:bids].fetch(actor_key, -1).to_i == 0
        return false if card.to_s.empty?

        completed = trick + [{ player: actor_key, card: card }]
        temporarily_winning = same_user?(trick_winner(completed), actor_key)

        suit = card_suit(card)
        rank = RANKS.index(card_rank(card)).to_i
        cheaper_loser = legal_cards(state, actor).any? do |candidate|
          next false if card_suit(candidate) != suit
          next false if RANKS.index(card_rank(candidate)).to_i >= rank

          candidate_trick = trick + [{ player: actor_key, card: candidate }]
          !same_user?(trick_winner(candidate_trick), actor_key)
        end
        return false if !cheaper_loser

        known_hands = context.is_a?(Hash) ? context[:known_hands] : nil
        if temporarily_winning
          return false if !known_hands.is_a?(Hash)

          return bot_last_opponent_overcard_promotes_control?(
            state, actor_key, card, known_hands
          )
        end
        if known_hands.is_a?(Hash)
          ordered = state[:players].flat_map do |player|
            key = player_key(state, player)
            known_hands.fetch(key) { hand_for(state, key).to_a }.map { |candidate| [key, candidate] }
          end.select { |_player, candidate| card_suit(candidate) == suit }
            .sort_by { |_player, candidate| -RANKS.index(card_rank(candidate)).to_i }
          controls = ordered.take_while { |player, _candidate| same_user?(player, actor_key) }
            .map(&:last)
          return controls.include?(card)
        end

        played = context.is_a?(Hash) ? context.fetch(:played_cards, []).to_a : []
        accounted = played + trick.map { |play| play[:card].to_s } + hand_for(state, actor_key).to_a
        deck_for(state[:players].length).none? do |candidate|
          card_suit(candidate) == suit &&
            RANKS.index(card_rank(candidate)).to_i > rank &&
            !accounted.include?(candidate)
        end
      end

      # The existing conservation rule normally sees a card only after it is
      # already losing. An omniscient bot in the penultimate seat can instead
      # know that its temporarily winning honor will be covered by the final
      # opponent. Preserve that honor when the covering card promotes it in the
      # hypothetical cheap-duck continuation.
      def bot_last_opponent_overcard_promotes_control?(state, actor, card, known_hands)
        trick = state[:current_trick].to_a
        return false if trick.empty?

        led_suit = card_suit(trick.first[:card])
        return false if card_suit(card) != led_suit

        actor_index = state[:players].index { |player| same_user?(player, actor) }
        return false if actor_index == nil

        remaining = state[:players].length - trick.length - 1
        return false if remaining != 1

        last_player = state[:players][(actor_index + 1) % state[:players].length]
        return false if bot_state_allied?(state, actor, last_player)

        last_key = player_key(state, last_player)
        last_hand = known_hands.fetch(last_key) { hand_for(state, last_key).to_a }
        legal_replies = legal_cards_for_led_suit(last_hand, led_suit)
        return false if legal_replies.empty?

        rank = RANKS.index(card_rank(card)).to_i
        cover = legal_replies.select do |candidate|
          card_suit(candidate) == led_suit &&
          RANKS.index(card_rank(candidate)).to_i > rank
        end.min_by { |candidate| RANKS.index(card_rank(candidate)).to_i }
        return false if cover == nil

        remaining_suit = state[:players].flat_map do |player|
          key = player_key(state, player)
          known_hands.fetch(key) { hand_for(state, key).to_a }
            .map { |candidate| [key, candidate] }
        end.select { |_player, candidate| card_suit(candidate) == led_suit }
        cover_index = remaining_suit.index do |player, candidate|
          same_user?(player, last_key) && candidate == cover
        end
        remaining_suit.delete_at(cover_index) if cover_index != nil
        controls = remaining_suit.sort_by do |_player, candidate|
          -RANKS.index(card_rank(candidate)).to_i
        end.take_while { |player, _candidate| same_user?(player, actor) }
          .map(&:last)
        controls.include?(card)
      end

      # When a bot has the lead, a top side-suit run may have only one or two
      # safe cashing opportunities before a short opponent can ruff. Prefer a
      # currently winning card from that run over a low card of the same suit.
      # Drawing trump or switching suits remains available to the round planner.
      def bot_expiring_control_score_adjustment(state, actor, action, context)
        control = if context.is_a?(Hash) && context.key?(:expiring_control)
          context[:expiring_control]
        else
          bot_expiring_contract_control(state, actor, context)
        end
        return 0.0 if control == nil

        card = action["card"].to_s
        return EXPIRING_CONTROL_PRIORITY if control[:control_cards].include?(card)
        return -EXPIRING_CONTROL_PRIORITY if card_suit(card) == control[:suit]

        0.0
      end

      def bot_expiring_contract_control(state, actor, context = nil)
        return nil if !state[:current_trick].to_a.empty?
        return nil if bot_contract_remaining(state, actor) <= 0

        exact = omniscient_bots?(state) ||
          (context.is_a?(Hash) && context[:known_hands].is_a?(Hash))
        return nil if !exact

        legal = legal_cards(state, actor)
        candidates = exact_side_suit_control_profile(state, actor).values.filter_map do |profile|
          next if profile[:safe_controls].to_i <= 0
          next if profile[:threatened_controls].to_i <= 0
          next if profile[:shortest_trump_opponent].to_i > 2

          controls = profile[:control_cards].select { |card| legal.include?(card) }
          next if controls.empty?

          profile.merge(
            control_cards: controls,
            preferred: controls.min_by { |card| bot_card_cost(state, card) }
          )
        end
        candidates.min_by do |profile|
          [profile[:shortest_trump_opponent], -profile[:threatened_controls], bot_card_cost(state, profile[:preferred])]
        end
      end

      # Fixed nil safety is intentionally independent from trained profile
      # weights and from the round planner. If a rollout is tied or unavailable,
      # the ordinary Spades policy still may not choose a card an opponent can
      # deliberately duck under. Among cards guaranteed to lose the trick, shed
      # the highest one first.
      def bot_nil_safety_score_adjustment(state, actor, action, context)
        actor_key = player_key(state, actor)
        return 0.0 if actor_key == nil
        return 0.0 if state[:bids].fetch(actor_key, -1).to_i != 0
        return 0.0 if state[:tricks].fetch(actor_key, 0).to_i != 0

        card = action["card"].to_s
        return 0.0 if card.empty?

        risk = bot_nil_retention_risk(state, actor_key, card, context)
        rank_value = RANKS.index(card_rank(card)).to_i / (RANKS.length - 1).to_f
        -80.0 * risk + 6.0 * rank_value * (1.0 - risk)
      end

      # Estimate whether the nil bidder can be left winning after all remaining
      # seats act. With complete hands this is a hostile exact calculation:
      # opponents duck whenever possible, while partners cover whenever
      # possible. Fair bots use the same method inside every sampled planning
      # world; outside the planner they retain a conservative public estimate.
      def bot_nil_retention_risk(state, actor, card, context = nil)
        actor_key = player_key(state, actor)
        return 0.0 if actor_key == nil

        trick = state[:current_trick] + [{ player: actor_key, card: card }]
        return 0.0 if !same_user?(trick_winner(trick), actor_key)

        remaining = state[:players].length - trick.length
        return 1.0 if remaining <= 0

        known_hands = context.is_a?(Hash) ? context[:known_hands] : nil
        if known_hands.is_a?(Hash)
          current = actor_key
          remaining.times do
            current = next_player(state[:players], current)
            current_key = player_key(state, current)
            hand = known_hands.fetch(current_key) { state[:hands].fetch(current_key, []) }
            led_suit = card_suit(trick.first[:card])
            legal = legal_cards_for_led_suit(hand, led_suit)
            return 0.0 if legal.empty?

            allied = bot_state_allied?(state, actor_key, current_key)
            preferred = legal.select do |reply|
              winner = trick_winner(trick + [{ player: current_key, card: reply }])
              allied ? !same_user?(winner, actor_key) : same_user?(winner, actor_key)
            end
            if preferred.empty?
              # An opponent that cannot duck is forced to cover the nil. An ally
              # that cannot cover plays cheaply and lets later seats try.
              return 0.0 if !allied
              chosen = legal.min_by { |reply| bot_card_cost(state, reply) }
            else
              chosen = preferred.min_by { |reply| bot_card_cost(state, reply) }
            end
            trick << { player: current_key, card: chosen }
            return 0.0 if !same_user?(trick_winner(trick), actor_key)
          end
          return 1.0
        end

        predicted_win = if context.is_a?(Hash)
          context.fetch(:win_probabilities, {}).fetch(card, 0.0).to_f
        else
          0.0
        end
        rank_value = RANKS.index(card_rank(card)).to_i / (RANKS.length - 1).to_f
        [[predicted_win + (1.0 - predicted_win) * rank_value, 0.0].max, 1.0].min
      end

      # Round planning is shared by all trained profiles. The learned policy
      # remains useful for local card technique and tie-breaking, while this
      # fixed adjustment makes complete-round consequences (contracts, bags,
      # nils and score position) matter in every Spades variant.
      def bot_planning_score_adjustment(state, _actor, action, context)
        plan = context.is_a?(Hash) ? context[:round_plan] : nil
        return 0.0 if !plan.is_a?(Hash)

        key = if state[:phase] == :bidding
          selection_value(action, "bid")
        else
          action["card"].to_s
        end
        score = plan.fetch(:scores, {})[key]
        return 0.0 if score == nil

        weight = state[:phase] == :bidding ? 7.0 : 9.0
        weight *= 1.2 if plan[:exact_information] == true
        raw_scores = plan.fetch(:raw_scores, {})
        raw_score = raw_scores[key]
        best_raw_score = raw_scores.values.compact.map(&:to_f).max
        total_cards = state[:hands].to_h.values.sum { |hand| hand.to_a.length }
        exact_continuation = state[:phase] == :playing &&
          plan[:exact_limit].to_i > 0 && total_cards <= plan[:exact_limit].to_i
        # A roughly thousand-point terminal swing denotes a projected match
        # result. Before the exact endgame boundary that result still depends on
        # heuristic rollout play, even when an omniscient bot knows every hand.
        # Do not let such an approximate projection use the unconditional veto;
        # the ordinary confidence-scaled adjustment below may still advise the
        # learned policy. Exact endgames retain the veto, as do ordinary
        # missed-contract outliers such as the build-80 dominated-lead case.
        approximate_match_loss = !exact_continuation && raw_score != nil &&
          raw_score.to_f <= -PLANNING_MATCH_LOSS_RAW_THRESHOLD
        # Confidence describes the margin between the two best choices. It may
        # legitimately be zero when several safe cards tie, but that must not
        # erase a decisive conclusion about a single losing outlier. Exact
        # complete-round evaluation can therefore veto a choice that trails the
        # best continuation by at least a missed-contract-sized swing, while the
        # learned policy remains responsible for choosing among the tied leaders.
        if plan[:exact_information] == true &&
            plan[:confidence].to_f < PLANNING_FULL_CONFIDENCE_MARGIN &&
            raw_score != nil && best_raw_score != nil &&
            best_raw_score - raw_score.to_f >= PLANNING_DOMINATED_RAW_MARGIN &&
            !approximate_match_loss
          return -PLANNING_DOMINATED_CHOICE_PENALTY
        end
        confidence_factor = if exact_continuation
          1.0
        elsif plan.key?(:confidence)
          [[plan[:confidence].to_f / PLANNING_FULL_CONFIDENCE_MARGIN, 0.0].max, 1.0].min
        else
          1.0
        end
        score.to_f * weight * confidence_factor
      end

      def playing_bot_features(replay, actor, action, context)
        state = replay.state
        card = action["card"].to_s
        rank_value = RANKS.index(card_rank(card)).to_i / (RANKS.length - 1).to_f
        trick = state[:current_trick]
        last_to_play = trick.length == state[:players].length - 1
        leader = trick.empty? ? nil : trick_winner(trick)
        winner_after = trick_winner(trick + [{ player: player_key(state, actor), card: card }])
        wins = same_user?(winner_after, actor)
        partner_winning = leader != nil && !same_user?(leader, actor) && bot_state_allied?(state, actor, leader)
        need = bot_contract_remaining(state, actor)
        own_bid = state[:bids].fetch(player_key(state, actor), -1).to_i
        own_tricks = state[:tricks].fetch(player_key(state, actor), 0).to_i
        nil_active = own_bid == 0 && own_tricks == 0
        led_suit = trick.empty? ? nil : card_suit(trick.first[:card])
        sloughing = led_suit != nil && card_suit(card) != led_suit
        actor_key = player_key(state, actor)
        assignment = team_assignment(state[:options], players: state[:players])
        teammates = assignment == nil ? [] : assignment.teammates_for(actor).reject { |player| same_user?(player, actor) }
        opponents = state[:players].reject do |player|
          same_user?(player, actor) || teammates.any? { |partner| same_user?(partner, player) }
        end
        active_nil = state[:players].select do |player|
          state[:bids].fetch(player, -1).to_i == 0 && state[:tricks].fetch(player, 0).to_i == 0
        end
        partner_nil = active_nil.find { |player| teammates.any? { |partner| same_user?(partner, player) } }
        opponent_nil = active_nil.find { |player| opponents.any? { |opponent| same_user?(opponent, player) } }
        protecting_partner_nil = partner_nil != nil
        partner_nil_has_played = partner_nil != nil && trick.any? do |play|
          same_user?(play[:player], partner_nil)
        end
        actor_index = state[:players].index { |player| same_user?(player, actor) }
        next_player = actor_index == nil ? nil : state[:players][(actor_index + 1) % state[:players].length]
        partner_nil_plays_next = partner_nil != nil && next_player != nil && same_user?(next_player, partner_nil)
        leader_is_partner_nil = leader != nil && partner_nil != nil && same_user?(leader, partner_nil)
        leader_is_opponent_nil = leader != nil && opponent_nil != nil && same_user?(leader, opponent_nil)
        higher_unseen = bot_higher_unseen_count(card, context[:unseen_cards])
        hand = hand_for(state, actor).to_a
        suit_length = hand.count { |candidate| card_suit(candidate) == card_suit(card) }
        void_suits = context[:void_suits]
        opponent_voids = opponents.count { |player| void_suits.fetch(player.to_s, []).include?(card_suit(card)) }
        partner_voids = teammates.count { |player| void_suits.fetch(player.to_s, []).include?(card_suit(card)) }
        score = context[:score]
        quicksand = state[:options]["quicksand"] == true
        non_spade_available = legal_cards(state, actor).any? { |candidate| card_suit(candidate) != "S" }
        win_probability = context.fetch(:win_probabilities, {}).fetch(card) do
          bot_trick_win_probability(state, actor, card, context)
        end
        # A high side-suit card is not a known winner when a player who still
        # has to act is publicly known to be void and may ruff it. Keep this in
        # sync with bot_trick_win_probability instead of looking only for a
        # higher card in the led suit.
        known_winner = higher_unseen == 0 && win_probability >= 1.0
        contract_plan = bot_contract_plan(state, actor, context)
        contract_pressure = protecting_partner_nil ? 1.0 : contract_plan[:contract_pressure]
        completed_avoidance = protecting_partner_nil ? 0.0 : contract_plan[:completed_avoidance_pressure]
        early_avoidance = protecting_partner_nil ? 0.0 : contract_plan[:early_avoidance_pressure]
        denial = nil_active ? { value: 0.0, forced: 0.0, tightness: 0.0 } :
          bot_opponent_contract_denial(state, actor, leader, wins, opponents)
        {
          "low_card" => 1.0 - rank_value,
          "trump_cost" => card_suit(card) == "S" ? -1.0 : 0.0,
          "last_win_needed" => last_to_play && wins ? contract_pressure : 0.0,
          "last_win_unneeded" => last_to_play && wins ? completed_avoidance : 0.0,
          "nil_win" => wins && nil_active ? 1.0 : 0.0,
          "protect_partner" => partner_winning && !wins ? 1.0 : 0.0,
          "overtake_partner" => partner_winning && wins ? 1.0 : 0.0,
          "discard_high" => sloughing && !wins && card_suit(card) != "S" ? rank_value : 0.0,
          "lead_spade" => trick.empty? && card_suit(card) == "S" ? 1.0 : 0.0,
          "win_before_last" => !last_to_play && need > 0 ? win_probability : 0.0,
          "bag_risk_win" => completed_avoidance > 0.0 && bot_bag_risk?(state, actor) ?
            win_probability * completed_avoidance : 0.0,
          "cheapest_winner" => win_probability >= 0.5 &&
            (protecting_partner_nil || contract_pressure >= [completed_avoidance, early_avoidance].max) &&
            context[:cheapest_winner] == card ? 1.0 : 0.0,
          "cash_contract_run" => context[:cash_contract_run] == card ? 1.0 : 0.0,
          "highest_safe_loser" => !wins && completed_avoidance > 0.0 && context[:highest_loser] == card ? completed_avoidance : 0.0,
          "needed_win_probability" => win_probability * contract_pressure,
          "unneeded_win_probability" => win_probability * completed_avoidance,
          "unneeded_high_release" => rank_value * (1.0 - win_probability) * completed_avoidance,
          "early_avoid_win_probability" => win_probability * early_avoidance,
          "early_avoid_high_release" => rank_value * (1.0 - win_probability) * early_avoidance,
          "early_avoid_safe_loser" => !wins && context[:highest_loser] == card ? early_avoidance : 0.0,
          "known_winner_needed" => known_winner && wins ? contract_pressure : 0.0,
          "waste_known_winner" => known_winner && !wins ? contract_pressure : 0.0,
          "higher_cards_unseen" => wins ? higher_unseen.to_f / [context[:unseen_cards].length, 1].max : 0.0,
          "lead_short_suit" => trick.empty? ? 1.0 - suit_length.to_f / [hand.length, 1].max : 0.0,
          "lead_into_opponent_void" => trick.empty? ? opponent_voids.to_f / [opponents.length, 1].max : 0.0,
          "lead_into_partner_void" => trick.empty? ? partner_voids.to_f / [teammates.length, 1].max : 0.0,
          "draw_trump" => trick.empty? && card_suit(card) == "S" && hand.count { |candidate| card_suit(candidate) == "S" } >= 3 ? 1.0 : 0.0,
          "partner_nil_cover" => leader_is_partner_nil && wins ? 1.0 : 0.0,
          "partner_nil_safe_lead" => trick.empty? && partner_nil != nil ? rank_value : 0.0,
          "partner_nil_lead_control" => protecting_partner_nil && trick.empty? ? win_probability : 0.0,
          # Taking control helps an active nil only when the partner still has to
          # play immediately after us, or when the partner is currently winning
          # the trick. Do not burn winners merely because we are leading, when
          # opponents can still intervene before the partner, or after the
          # partner has already discarded safely.
          "partner_nil_control" => protecting_partner_nil && !trick.empty? &&
            ((!partner_nil_has_played && partner_nil_plays_next) || leader_is_partner_nil) ? win_probability : 0.0,
          "partner_nil_distant_control" => protecting_partner_nil && !trick.empty? &&
            !partner_nil_has_played && !partner_nil_plays_next ? win_probability : 0.0,
          "opponent_nil_feed" => leader_is_opponent_nil && !wins ? 1.0 : 0.0,
          "opponent_nil_pressure" => trick.empty? && opponent_nil != nil ? 1.0 - rank_value : 0.0,
          "deny_opponent_contract" => denial[:value],
          "force_opponent_set" => denial[:forced],
          "tight_table_denial" => denial[:tightness],
          "trailing_contract_win" => win_probability * [score[:deficit], 0.0].max * contract_pressure,
          "leading_avoid_extra" => win_probability * [-score[:deficit], 0.0].max * completed_avoidance,
          "quicksand_extra_win" => quicksand ? win_probability * completed_avoidance : 0.0,
          "quicksand_needed_win" => quicksand ? win_probability * contract_pressure : 0.0,
          "bag_penalty_imminent" => !quicksand && completed_avoidance > 0.0 && score[:bags] >= 8 ?
            win_probability * completed_avoidance : 0.0,
          "preserve_trump" => card_suit(card) == "S" && !wins && non_spade_available ? -1.0 : 0.0
        }
      end

      def bot_public_play_context(replay)
        events = GameRoomParticipantDecisionEvents.for(replay).to_a
        last_deal = events.rindex { |event| event["action"].to_s == "deal" }
        round_events = last_deal == nil ? [] : events[(last_deal + 1)..]
        plays = round_events.to_a.select { |event| event["action"].to_s == "play" }
        void_suits = Hash.new { |hash, player| hash[player] = [] }
        ace_played = plays.any? { |event| event["value"].to_s == "AS" }
        plays.each_slice(replay.players.length) do |trick|
          next if trick.empty?

          led_suit = card_suit(trick.first["value"])
          trick.each do |event|
            next if card_suit(event["value"]) == led_suit

            player = event["actor"].to_s
            missing = led_suit == "S" && !ace_played ? "S_except_ace" : led_suit
            void_suits[player] << missing if !void_suits[player].include?(missing)
          end
        end
        {
          played_cards: plays.map { |event| event["value"].to_s },
          public_plays: plays.map do |event|
            { player: event["actor"].to_s, card: event["value"].to_s }
          end,
          void_suits: void_suits
        }
      end

      def bot_card_wins?(state, actor, card)
        winner = trick_winner(state[:current_trick] + [{ player: player_key(state, actor), card: card }])
        same_user?(winner, actor)
      end

      def bot_card_cost(state, card)
        led_suit = state[:current_trick].empty? ? card_suit(card) : card_suit(state[:current_trick].first[:card])
        trump = card_suit(card) == "S" && led_suit != "S" ? 1 : 0
        [trump, RANKS.index(card_rank(card)).to_i]
      end

      # A long run of reliable winners can disappear as soon as opponents become
      # void and start ruffing. Early bag avoidance may still shed genuinely
      # spare tricks, but it must first cash enough cards from such a run to make
      # the outstanding contract. Requiring one winner more than the current need
      # keeps the existing cautious behavior for isolated aces and other single
      # controls while protecting sequences such as A-K-Q-J.
      def bot_cash_contract_run(state, actor, reliable_winners)
        return nil if !state[:current_trick].empty?

        need = bot_contract_remaining(state, actor)
        return nil if need <= 0

        runs = reliable_winners.group_by { |card| card_suit(card) }.values.filter_map do |cards|
          next if cards.length <= need

          cards.min_by { |card| bot_card_cost(state, card) }
        end
        runs.min_by { |card| bot_card_cost(state, card) }
      end

      def bot_higher_unseen_count(card, unseen_cards)
        rank = RANKS.index(card_rank(card)).to_i
        unseen_cards.count do |candidate|
          card_suit(candidate) == card_suit(card) && RANKS.index(card_rank(candidate)).to_i > rank
        end
      end

      def bot_contract_plan(state, actor, context = nil)
        assignment = team_assignment(state[:options], players: state[:players])
        actor_key = player_key(state, actor)
        members = assignment == nil ? [actor_key] : assignment.teammates_for(actor)
        regular = members.reject { |player| state[:bids].fetch(player, -1).to_i == 0 }
        required = regular.sum { |player| state[:bids].fetch(player, 0).to_i }
        won = regular.sum { |player| state[:tricks].fetch(player, 0).to_i }
        need = [required - won, 0].max
        partner_expected = regular.reject { |player| same_user?(player, actor) }.sum do |player|
          [state[:bids].fetch(player, 0).to_i - state[:tricks].fetch(player, 0).to_i, 0].max
        end
        actor_required = [need - partner_expected, 0].max
        remaining = [hand_for(state, actor).to_a.length, 1].max
        probable = estimated_bot_bid(state, actor)
        certain = estimated_certain_tricks(state, actor).to_f
        probable_surplus = probable - actor_required
        certain_surplus = certain - actor_required
        projected_winners = if state[:current_trick].empty? && context != nil &&
            context[:win_probabilities].is_a?(Hash)
          context[:win_probabilities].values.sum(&:to_f)
        else
          probable
        end
        projected_overtricks = [projected_winners - actor_required, 0.0].max

        if need <= 0
          completed_avoidance = bot_overtrick_avoidance_pressure(
            state, actor, [projected_winners, 0.0].max
          )
          return {
            contract_pressure: 0.0,
            completed_avoidance_pressure: completed_avoidance,
            early_avoidance_pressure: 0.0,
            avoidance_pressure: completed_avoidance,
            probable_surplus: probable_surplus,
            certain_surplus: certain_surplus,
            projected_overtricks: projected_overtricks
          }
        end

        urgency = [[actor_required.to_f / remaining, 0.0].max, 1.0].min
        shortage = [-probable_surplus, 0.0].max / [actor_required, 1].max.to_f
        contract_pressure = [urgency + shortage + (certain_surplus < 0.0 ? 0.25 : 0.0), 1.0].min
        # One accidental overtrick is normally cheaper than breaking a contract.
        # Start ducking early only with at least two independently projected spare
        # tricks, and scale that caution using public card probabilities and the
        # number of bags already carried by this player or team.
        minimum_early_surplus = 2.0
        covered_surplus = [certain_surplus, probable_surplus].max
        avoidance_pressure = if covered_surplus >= minimum_early_surplus
          bot_overtrick_avoidance_pressure(state, actor, projected_overtricks) * 0.75
        else
          0.0
        end
        {
          contract_pressure: contract_pressure,
          completed_avoidance_pressure: 0.0,
          early_avoidance_pressure: avoidance_pressure,
          avoidance_pressure: avoidance_pressure,
          probable_surplus: probable_surplus,
          certain_surplus: certain_surplus,
          projected_overtricks: projected_overtricks
        }
      end

      def bot_overtrick_avoidance_pressure(state, actor, projected_overtricks)
        extras = [projected_overtricks.to_f, 0.0].max
        return 0.0 if extras <= 0.0
        return 1.0 if state[:options]["quicksand"] == true

        bags = bot_score_context(state, actor)[:bags].to_i
        bag_ratio = [[bags.to_f / 9.0, 0.0].max, 1.0].min
        tolerated = 1.0 - bag_ratio * 0.75
        excess = extras - tolerated
        return 0.0 if excess <= 0.0

        [[0.2 + excess * 0.35 + bag_ratio * 0.5, 0.0].max, 1.0].min
      end

      def bot_regular_contract(state, actor)
        assignment = team_assignment(state[:options], players: state[:players])
        members = assignment == nil ? [player_key(state, actor)] : assignment.teammates_for(actor)
        regular = members.reject { |player| state[:bids].fetch(player, -1).to_i == 0 }
        bid = regular.sum { |player| state[:bids].fetch(player, 0).to_i }
        tricks = regular.sum { |player| state[:tricks].fetch(player, 0).to_i }
        { bid: bid, tricks: tricks, need: [bid - tricks, 0].max }
      end

      def bot_opponent_contract_denial(state, actor, leader, wins, opponents)
        return { value: 0.0, forced: 0.0, tightness: 0.0 } if leader == nil || !wins
        return { value: 0.0, forced: 0.0, tightness: 0.0 } if !opponents.any? { |player| same_user?(player, leader) }

        contract = bot_regular_contract(state, leader)
        return { value: 0.0, forced: 0.0, tightness: 0.0 } if contract[:need] <= 0

        remaining = [hand_for(state, actor).to_a.length, 1].max
        remaining_after = [remaining - 1, 0].max
        maximum = [cards_per_player(state[:players].length), 1].max
        total_bids = state[:bids].values.sum(&:to_i)
        urgency = [contract[:need].to_f / remaining, 1.0].min
        contract_value = [contract[:bid].to_f / maximum, 1.0].min
        tightness = [[total_bids.to_f / maximum - 0.65, 0.0].max, 1.0].min
        {
          value: [0.25 + urgency * 0.5 + contract_value * 0.5, 1.5].min,
          forced: contract[:need] > remaining_after ? 1.0 : 0.0,
          tightness: tightness
        }
      end

      # Estimate whether a card that is provisionally winning will still win
      # after the remaining players act. Only the public trick, the actor's hand
      # and unseen cards are used. This lets a bot that has made its contract
      # distinguish a genuinely dangerous winner from a high card that can be
      # safely shed under a likely higher card.
      def bot_trick_win_probability(state, actor, card, context)
        if context[:omniscient] == true
          return bot_exact_trick_win_probability(state, actor, card, context)
        end

        actor_key = player_key(state, actor)
        trick = state[:current_trick] + [{ player: actor_key, card: card }]
        return 0.0 if !same_user?(trick_winner(trick), actor)

        remaining_players = state[:players].length - trick.length
        return 1.0 if remaining_players <= 0

        led_suit = card_suit(trick.first[:card])
        winning_play = trick.find { |play| same_user?(play[:player], actor_key) }
        winning_card = winning_play[:card]
        winning_suit = card_suit(winning_card)
        winning_rank = RANKS.index(card_rank(winning_card)).to_i
        threats = context[:unseen_cards].count do |candidate|
          candidate_suit = card_suit(candidate)
          candidate_rank = RANKS.index(card_rank(candidate)).to_i
          if winning_suit == "S"
            candidate_suit == "S" && candidate_rank > winning_rank
          else
            candidate_suit == led_suit && candidate_rank > winning_rank
          end
        end
        unknown = context[:unseen_cards].length
        slots = [remaining_players * hand_for(state, actor).to_a.length, unknown].min
        probability_no_threat = bot_probability_without_targets(unknown, threats, slots)

        # A side-suit winner can also lose to a ruff. Public play history tells
        # us which players are already void in the led suit. Estimate the chance
        # that none of the remaining spades is in the hands of those players.
        # If every remaining player is void, any unseen spade makes the ruff
        # certain; with only one known void the result remains probabilistic.
        if winning_suit != "S" && led_suit != "S"
          future_players = state[:players].reject do |player|
            trick.any? { |play| same_user?(play[:player], player) }
          end
          void_players = future_players.count do |player|
            context[:void_suits].fetch(player.to_s, []).include?(led_suit)
          end
          if void_players > 0
            unseen_spades = context[:unseen_cards].count { |candidate| card_suit(candidate) == "S" }
            void_slots = [void_players * hand_for(state, actor).to_a.length, unknown].min
            probability_no_threat *= bot_probability_without_targets(unknown, unseen_spades, void_slots)
          end
        end
        [[probability_no_threat, 0.0].max, 1.0].min
      end

      # Resolve the rest of the current trick against the actual remaining
      # hands. Opponents choose a reply that defeats the candidate whenever one
      # exists, while partners cooperate. This is a compact double-dummy search
      # over one trick rather than an expensive search over the entire match.
      def bot_exact_trick_win_probability(state, actor, card, context)
        actor_key = player_key(state, actor)
        trick = state[:current_trick] + [{ player: actor_key, card: card }]
        return 0.0 if !same_user?(trick_winner(trick), actor)

        remaining = state[:players].length - trick.length
        return 1.0 if remaining <= 0

        actor_index = state[:players].index { |player| same_user?(player, actor) }
        return 0.0 if actor_index == nil

        future_players = (1..remaining).map do |offset|
          state[:players][(actor_index + offset) % state[:players].length]
        end
        bot_exact_trick_outcome(
          state,
          actor,
          trick,
          future_players,
          context.fetch(:known_hands)
        ) ? 1.0 : 0.0
      end

      def bot_exact_trick_outcome(state, actor, trick, future_players, known_hands)
        if future_players.empty?
          return same_user?(trick_winner(trick), actor)
        end

        player = future_players.first
        hand = known_hands.fetch(player_key(state, player), [])
        led_suit = card_suit(trick.first[:card])
        legal = legal_cards_for_led_suit(hand, led_suit)
        return same_user?(trick_winner(trick), actor) if legal.empty?

        cooperative = bot_state_allied?(state, actor, player)
        legal.each do |candidate|
          actor_wins = bot_exact_trick_outcome(
            state,
            actor,
            trick + [{ player: player_key(state, player), card: candidate }],
            future_players.drop(1),
            known_hands
          )
          return true if cooperative && actor_wins
          return false if !cooperative && !actor_wins
        end
        !cooperative
      end

      def spades_round_planner
        @spades_round_planner ||= SpadesPlanning::RoundPlanner.new(self)
      end

      def bot_probability_without_targets(unknown, targets, slots)
        available_cards = [unknown.to_i, 0].max
        target_cards = [[targets.to_i, 0].max, available_cards].min
        draws = [[slots.to_i, 0].max, available_cards].min
        return 1.0 if target_cards == 0 || draws == 0

        probability = 1.0
        draws.times do |index|
          available = available_cards - index
          safe = available_cards - target_cards - index
          return 0.0 if safe <= 0

          probability *= safe.to_f / available
        end
        probability
      end
    end

    include PlayEvaluation
    public :bot_future_control_discard?, :bot_expiring_contract_control, :bot_planning_score_adjustment
  end
end
