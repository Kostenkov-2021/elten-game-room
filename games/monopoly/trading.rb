require_relative '../../lib/game_room_localization'

module GameRoomGames
  using GameRoomLocalization::Translations
  class Monopoly
    module Trading
      private

      def apply_trade(state, event, actor, repository, history)
        action = event["action"].to_s
        id = repository.event_id(event)
        if action == "trade_prepare"
          return false if ![:awaiting_roll, :turn_complete].include?(state[:phase]) || !same_user?(state[:current_player], actor)
          target_index = Integer(event["value"].to_s, 36)
          target = state[:players][target_index]
          player = player_key(state, actor)
          return false if target == nil || same_user?(target, player) || !active_players(state).include?(target)

          history << HistoryEntry.new(key: "trade_prepare:#{id}", text: _("%{player} is preparing a trade offer for %{target}.") % {
            player: participant_name(player), target: participant_name(target)
          }, event_id: id, actor: actor, kind: :game)
          return true
        end
        if action == "trade_offer"
          return false if ![:awaiting_roll, :turn_complete].include?(state[:phase]) || !same_user?(state[:current_player], actor)
          offer = parse_trade_offer(state, event["value"])
          return false if offer == nil
          offer[:from] = player_key(state, actor)
          return false if !valid_trade_offer?(state, offer)
          offer[:encoded] = event["value"].to_s
          state[:trade_offered_turn][offer[:from]] = state[:turn_number]
          state[:trade_target_turn][[offer[:from], offer[:target]]] = state[:turn_number]
          state[:trade_offer] = offer
          state[:trade_phase] = state[:phase]
          state[:phase] = :trade_response
          state[:current_player] = offer[:target]
          history << HistoryEntry.new(key: "trade_offer:#{id}", text: _("%{player} proposed a trade to %{target}: %{offer}.") % {
            player: participant_name(offer[:from]), target: participant_name(offer[:target]), offer: public_trade_summary(state, offer)
          }, event_id: id, actor: actor, kind: :game)
          return true
        end

        offer = state[:trade_offer]
        return false if state[:phase] != :trade_response || offer == nil || !same_user?(state[:current_player], actor) || !same_user?(offer[:target], actor)
        if action == "trade_accept"
          return false if !valid_trade_offer?(state)
          execute_trade(state, offer)
          text = _("Trade completed: %{details}.") % { details: public_trade_summary(state, offer) }
        elsif action == "trade_reject"
          state[:rejected_trades]["#{offer[:from]}|#{offer[:encoded]}"] = true
          text = _("%{player} rejected the offer from %{proposer}.") % { player: participant_name(actor), proposer: participant_name(offer[:from]) }
        else
          return false
        end
        proposer = offer[:from]
        history << HistoryEntry.new(key: "trade_result:#{id}", text: text, event_id: id, actor: actor, kind: :game)
        state[:current_player] = proposer
        state[:phase] = state[:trade_phase] || :turn_complete
        state[:trade_offer] = nil
        state[:trade_phase] = nil
        true
      rescue ArgumentError, TypeError
        false
      end

      def trade_actions(state, player)
        return [] if player == nil
        own = tradeable_squares(state, player)
        active_players(state).reject { |target| same_user?(target, player) }.flat_map do |target|
          theirs = tradeable_squares(state, target)
          target_index = player_index(state[:players], target)
          offers = own.map do |square|
            encode_trade_offer(target: target_index, give_property: square[:index], receive_cash: square[:price])
          end
          offers.concat(theirs.filter_map do |square|
            next if state[:cash][player].to_i < square[:price].to_i
            encode_trade_offer(target: target_index, receive_property: square[:index], give_cash: square[:price])
          end)
          offers.concat(own.product(theirs).map do |given, received|
            encode_trade_offer(target: target_index, give_property: given[:index], receive_property: received[:index])
          end)
          # Add negotiated prices, sharing the gain from completing a group.
          # Exact face-value offers remain legal for the human trade form/replay.
          [[own, player, target, true], [theirs, target, player, false]].each do |squares, seller, buyer, selling|
            squares.each do |square|
              probe = parse_trade_offer(state, encode_trade_offer(target: target_index,
                give_property: selling ? square[:index] : -1, receive_property: selling ? -1 : square[:index]))
              probe[:from] = player
              loss = -trade_gain(state, probe, seller)
              gain = trade_gain(state, probe, buyer)
              next if gain <= loss + money(state, 20)
              price = (loss + gain) / 2
              offers << encode_trade_offer(target: target_index,
                give_property: selling ? square[:index] : -1, receive_property: selling ? -1 : square[:index],
                receive_cash: selling ? price : 0, give_cash: selling ? 0 : price)
            end
          end
          offers.map { |offer| { "kind" => "command", "action" => "trade_offer", "offer" => offer } }
        end
      end

      def tradeable_squares(state, player)
        owned_squares(state, player).select { |square| tradeable_index?(state, square[:index]) }
      end

      def encode_trade_offer(target:, give_property: -1, receive_property: -1, give_properties: nil, receive_properties: nil, give_cash: 0, receive_cash: 0)
        give = normalize_offer_indices(give_properties, give_property)
        receive = normalize_offer_indices(receive_properties, receive_property)
        [
          TRADE_OFFER_VERSION,
          Integer(target.to_s, 10).to_s(36),
          property_mask(give).to_s(36),
          property_mask(receive).to_s(36),
          Integer(give_cash.to_s, 10),
          Integer(receive_cash.to_s, 10)
        ].join("|")
      end

      def parse_trade_offer(state, value)
        parts = value.to_s.split("|", -1)
        if parts.length == 6 && parts.first == TRADE_OFFER_VERSION
          target_index = Integer(parts[1], 36)
          give_mask = Integer(parts[2], 36)
          receive_mask = Integer(parts[3], 36)
          give_cash = Integer(parts[4], 10)
          receive_cash = Integer(parts[5], 10)
          return nil if give_mask < 0 || receive_mask < 0
          return nil if (give_mask >> state[:board].length) != 0 || (receive_mask >> state[:board].length) != 0
          give = indices_from_property_mask(give_mask, state[:board].length)
          receive = indices_from_property_mask(receive_mask, state[:board].length)
        elsif value.to_s.start_with?("{")
          data = JSON.parse(value)
          target_index = data.fetch("target")
          return nil if !target_index.is_a?(Integer)
          give = data.fetch("give_properties")
          receive = data.fetch("receive_properties")
          return nil if !give.is_a?(Array) || !receive.is_a?(Array)
          return nil if (give + receive).any? { |index| !index.is_a?(Integer) || index < 0 }
          give_cash, receive_cash = data.fetch("give_cash"), data.fetch("receive_cash")
          return nil if !give_cash.is_a?(Integer) || !receive_cash.is_a?(Integer)
        else
          return nil if parts.length != 5
          target_index, given, received, give_cash, receive_cash = parts.map { |part| Integer(part, 10) }
          return nil if given < -1 || received < -1
          give, receive = given == -1 ? [] : [given], received == -1 ? [] : [received]
        end
        return nil if !target_index.between?(0, state[:players].length - 1) || give.uniq != give || receive.uniq != receive
        { target: state[:players][target_index], give_property: give.first || -1, receive_property: receive.first || -1,
          give_properties: give, receive_properties: receive, give_cash: give_cash, receive_cash: receive_cash }
      rescue ArgumentError, TypeError, KeyError, JSON::ParserError
        nil
      end

      def normalize_offer_indices(indices, single)
        values = indices == nil ? (single.to_i < 0 ? [] : [single]) : indices.to_a
        values.map { |index| Integer(index.to_s, 10) }.uniq.sort
      end

      def property_mask(indices)
        indices.to_a.reduce(0) do |mask, index|
          raise ArgumentError, "invalid property index" if index.to_i < 0
          mask | (1 << index.to_i)
        end
      end

      def indices_from_property_mask(mask, board_length)
        board_length.times.select { |index| (mask & (1 << index)) != 0 }
      end

      def empty_trade_offer?(offer)
        offer_properties(offer, :give).empty? && offer_properties(offer, :receive).empty? &&
          offer[:give_cash].to_i == offer[:receive_cash].to_i
      end

      def valid_trade_offer?(state, offer = state[:trade_offer])
        return false if offer == nil || !active_players(state).include?(offer[:from]) || !active_players(state).include?(offer[:target])
        return false if same_user?(offer[:from], offer[:target])
        return false if offer[:give_cash] < 0 || offer[:receive_cash] < 0
        return false if offer[:give_cash] > TRADE_CASH_LIMIT || offer[:receive_cash] > TRADE_CASH_LIMIT
        return false if empty_trade_offer?(offer)
        return false if offer[:give_cash] > 0 && state[:cash][offer[:from]].to_i + offer[:receive_cash] < offer[:give_cash]
        return false if offer[:receive_cash] > 0 && state[:cash][offer[:target]].to_i + offer[:give_cash] < offer[:receive_cash]
        offer_properties(offer, :give).each do |index|
          return false if !same_user?(state[:owners][index], offer[:from]) || !tradeable_index?(state, index)
        end
        offer_properties(offer, :receive).each do |index|
          return false if !same_user?(state[:owners][index], offer[:target]) || !tradeable_index?(state, index)
        end
        true
      end

      def tradeable_index?(state, index)
        square = state[:board][index]
        square != nil && [:property, :railroad, :utility].include?(square[:type]) &&
          state[:houses][index].to_i.zero? && !state[:mortgaged][index] &&
          (square[:type] != :property || colour_group_squares(state, square[:group]).all? { |property| state[:houses][property[:index]].to_i.zero? })
      end

      def execute_trade(state, offer)
        from = offer[:from]
        target = offer[:target]
        state[:cash][from] += offer[:receive_cash] - offer[:give_cash]
        state[:cash][target] += offer[:give_cash] - offer[:receive_cash]
        offer_properties(offer, :give).each { |index| state[:owners][index] = target }
        offer_properties(offer, :receive).each { |index| state[:owners][index] = from }
      end

      def offer_properties(offer, side)
        offer["#{side}_properties".to_sym] || (offer["#{side}_property".to_sym].to_i >= 0 ? [offer["#{side}_property".to_sym]] : [])
      end
    end

    include Trading
  end
end
