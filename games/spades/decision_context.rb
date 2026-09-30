require_relative '../../lib/game_room_localization'

module GameRoomGames
  using GameRoomLocalization::Translations
  class Spades
    module DecisionContext
      public

      def bot_observation(replay, actor)
        state = replay.state
        {
          "players" => state[:players],
          "scores" => state[:scores],
          "round" => state[:round],
          "phase" => state[:phase],
          "current_player" => state[:current_player],
          "hand" => hand_for(state, actor).to_a,
          "opponent_card_counts" => state[:players].each_with_object({}) do |candidate, result|
            result[candidate] = state[:hands].fetch(candidate, []).length if !same_user?(candidate, actor)
          end,
          "bids" => state[:bids],
          "tricks" => state[:tricks],
          "current_trick" => state[:current_trick],
          "spades_broken" => state[:spades_broken],
          "winner" => state[:winner]
        }
      end

      def bot_action_score(replay, actor, action, context: nil)
        state = replay.state
        if action["action"].to_s.start_with?("bid_")
          hand = hand_for(state, actor).to_a
          strong = hand.count { |card| ["A", "K"].include?(card_rank(card)) }
          strong += hand.count { |card| card_suit(card) == "S" && RANKS.index(card_rank(card)).to_i >= 8 }
          target = [[strong, 0].max, cards_per_player(state[:players].length)].min
          bid = selection_value(action, "bid")
          return 1_000.0 - (bid - target).abs * 100.0
        end

        card = action["card"].to_s
        rank = RANKS.index(card_rank(card)).to_i
        trump = card_suit(card) == "S" ? 20 : 0
        if state[:current_trick].empty?
          return -(rank + trump).to_f
        end

        led = card_suit(state[:current_trick].first[:card])
        follows = card_suit(card) == led
        -(rank + trump).to_f + (follows ? 5.0 : 0.0)
      end

      # Fair bots compute every feature from the player's own hand, public
      # scores, bids and the public play log. A table may explicitly enable the
      # separate omniscient challenge mode, whose private decision context also
      # contains the remaining hands. The public bot observation stays fair in
      # both modes, so private cards never leak into the player-facing API.
      def bot_action_features(replay, actor, action, context: nil)
        state = replay.state
        return bidding_bot_features(state, actor, action) if state[:phase] == :bidding
        return playing_bot_features(replay, actor, action, context || bot_decision_context(replay, actor)) if state[:phase] == :playing

        {}
      end

      # This context is shared by every candidate card in one decision. Apart
      # from making decisions faster, it keeps the intentional information
      # boundary in one auditable place.
      def bot_decision_context(replay, actor, plan_round: true)
        state = replay.state
        public_context = bot_public_play_context(replay)
        hand = hand_for(state, actor).to_a
        played_cards = public_context[:played_cards]
        unseen_cards = deck_for(state[:players].length) - hand - played_cards
        omniscient = omniscient_bots?(state)
        known_hands = if omniscient
          state[:players].each_with_object({}) do |player, result|
            result[player_key(state, player)] = hand_for(state, player).to_a.dup
          end
        end
        void_suits = if omniscient
          known_hands.each_with_object({}) do |(player, cards), result|
            result[player.to_s] = SUITS.select do |suit|
              cards.none? { |card| card_suit(card) == suit }
            end
          end
        else
          public_context[:void_suits].each_with_object({}) do |(player, suits), result|
            result[player.to_s] = suits.to_a.dup
          end
        end
        state[:players].each do |player|
          next if same_user?(player, actor)

          entry = (void_suits[player.to_s] ||= [])
          SUITS.each do |suit|
            # If every unplayed card of a suit is in our own hand, public card
            # counting proves that every opponent is void even when nobody has
            # failed to follow that suit yet.
            next if unseen_cards.any? { |card| card_suit(card) == suit }

            entry << suit if !entry.include?(suit)
          end
        end
        legal = legal_cards(state, actor)
        probability_context = {
          played_cards: played_cards,
          void_suits: void_suits,
          unseen_cards: unseen_cards,
          omniscient: omniscient,
          known_hands: known_hands
        }
        win_probabilities = legal.each_with_object({}) do |card, result|
          result[card] = bot_trick_win_probability(state, actor, card, probability_context)
        end
        winning_cards = legal.select { |card| win_probabilities.fetch(card, 0.0) >= 0.5 }
        losing_cards = legal - winning_cards
        result = {
          omniscient: omniscient,
          played_cards: played_cards,
          public_plays: public_context[:public_plays],
          void_suits: void_suits,
          unseen_cards: unseen_cards,
          win_probabilities: win_probabilities,
          winning_cards: winning_cards,
          cheapest_winner: winning_cards.min_by { |card| bot_card_cost(state, card) },
          cash_contract_run: bot_cash_contract_run(state, actor, winning_cards),
          highest_loser: losing_cards.reject { |card| card_suit(card) == "S" }.max_by { |card| RANKS.index(card_rank(card)).to_i },
          score: bot_score_context(state, actor)
        }
        result[:known_hands] = known_hands if omniscient
        if state[:phase] == :playing
          result[:expiring_control] = bot_expiring_contract_control(state, actor, result)
        end
        result[:round_plan] = if plan_round
          spades_round_planner.plan(state: state, actor: actor, information: result)
        else
          { phase: state[:phase], scores: {}, raw_scores: {}, worlds: 0, exact_information: false }
        end
        if state[:phase] == :bidding
          result[:bid_threat] = bot_bid_threat_context(state, actor, result[:round_plan])
        end
        result
      end
    end

    include DecisionContext
  end
end
