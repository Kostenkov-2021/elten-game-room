require_relative '../../lib/game_room_localization'

module GameRoomGames
  using GameRoomLocalization::Translations
  class Monopoly
    module PropertyManagement
      private

      def apply_buy(state, event, actor, repository, history)
        return false if state[:phase] != :property_decision || !same_user?(state[:current_player], actor)
        player = player_key(state, actor)
        square = current_square(state, player)
        return false if state[:owners][square[:index]] != nil || state[:cash][player] < square[:price].to_i
        state[:cash][player] -= square[:price].to_i
        state[:owners][square[:index]] = player
        state[:phase] = :turn_complete
        history << HistoryEntry.new(
          key: "buy:#{repository.event_id(event)}",
          text: _("%{player} bought %{property}, %{group}, for %{price}.") % {
            player: participant_name(player), property: square[:name],
            group: property_group_label(square), price: square[:price]
          },
          event_id: repository.event_id(event), actor: actor, kind: :game
        )
        true
      end

      def apply_decline(state, event, actor, repository, history)
        return false if state[:phase] != :property_decision || !same_user?(state[:current_player], actor)
        square = current_square(state, actor)
        id = repository.event_id(event)
        history << HistoryEntry.new(key: "decline:#{id}", text: _("%{player} declined %{property}.") % { player: participant_name(actor), property: square[:name] }, event_id: id, actor: actor, kind: :game)
        if state[:options]["auction_unsold"]
          state[:phase] = :auction
          state[:auction_square] = square[:index]
          state[:auction_bid] = 0
          state[:auction_leader] = nil
          state[:auction_passed] = {}
          state[:auction_origin] = actor
          state[:current_player] = next_active_player(state, actor)
          set_auction_deadline(state, event["value"].to_i, id)
          history << HistoryEntry.new(key: "auction_start:#{id}", text: _("Auction begins: %{property}.") % { property: property_name_and_group(square) }, event_id: id, actor: actor, kind: :game)
        else
          state[:phase] = :turn_complete
        end
        true
      end

      def apply_property_action(state, event, actor, repository, history)
        action = event["action"].to_s
        index = Integer(event["value"].to_s, 10)
        player = player_key(state, actor)
        return false if !same_user?(state[:current_player], actor) || ![:awaiting_roll, :turn_complete].include?(state[:phase]) || !same_user?(state[:owners][index], player)
        square = state[:board][index]
        # Menu rows contain costs and building counts. Confirmations are separate
        # sentences so speech/history do not repeat that management information.
        case action
        when "build"
          return false if !can_build?(state, player, square)
          description = [
            _("%{player} builds the first house on %{property}."),
            _("%{player} builds the second house on %{property}."),
            _("%{player} builds the third house on %{property}."),
            _("%{player} builds the fourth house on %{property}."),
            _("%{player} builds a hotel on %{property}.")
          ].fetch(state[:houses][index].to_i)
          state[:cash][player] -= square[:house_cost]
          state[:houses][index] += 1
        when "sell"
          return false if !can_sell_building?(state, player, square)
          if hotel_liquidation?(state, square)
            description = _("%{player} sells all buildings in the %{group}.")
            # Without four available houses a hotel cannot be downgraded.
            # The explicitly labelled alternative sells the whole colour group.
            colour_group_squares(state, square[:group]).each do |property|
              level = state[:houses][property[:index]].to_i
              state[:cash][player] += level * property[:house_cost] / 2
              state[:houses][property[:index]] = 0
            end
          else
            description = state[:houses][index] == 5 ? _("%{player} sells a hotel on %{property}.") : _("%{player} sells a house on %{property}.")
            state[:houses][index] -= 1
            state[:cash][player] += square[:house_cost] / 2
          end
        when "mortgage"
          return false if !can_mortgage?(state, player, square)
          description = _("%{player} mortgages %{property}.")
          state[:mortgaged][index] = true
          state[:cash][player] += square[:mortgage]
        when "unmortgage"
          cost = unmortgage_cost(square)
          return false if !state[:mortgaged][index] || state[:cash][player] < cost
          description = _("%{player} unmortgages %{property}.")
          state[:mortgaged].delete(index)
          state[:cash][player] -= cost
        else
          return false
        end
        id = repository.event_id(event)
        history << HistoryEntry.new(key: "property:#{id}", text: description % {
          player: participant_name(player), property: square[:name], group: property_group_label(square)
        }, event_id: id, actor: actor, kind: :game)
        true
      rescue ArgumentError
        false
      end

      def management_actions(state, player)
        actions = []
        owned_squares(state, player).each do |square|
          index = square[:index].to_s
          if can_build?(state, player, square)
            actions << { "kind" => "command", "action" => "build", "property" => index }
          end
          actions << { "kind" => "command", "action" => "sell", "property" => index } if can_sell_building?(state, player, square)
          actions << { "kind" => "command", "action" => "mortgage", "property" => index } if can_mortgage?(state, player, square)
          cost = unmortgage_cost(square)
          actions << { "kind" => "command", "action" => "unmortgage", "property" => index } if state[:mortgaged][square[:index]] && state[:cash][player] >= cost
        end
        actions
      end

      def owns_group?(state, player, group)
        squares = colour_group_squares(state, group)
        squares.length > 1 && squares.all? { |square| same_user?(state[:owners][square[:index]], player) }
      end

      def colour_group_squares(state, group)
        state[:board].select { |square| square[:type] == :property && square[:group] == group }
      end

      def can_build?(state, player, square)
        return false if square == nil || square[:type] != :property || !owns_group?(state, player, square[:group])
        group = colour_group_squares(state, square[:group])
        return false if group.any? { |property| state[:mortgaged][property[:index]] }
        return false if state[:houses][square[:index]].to_i >= 5 || state[:cash][player].to_i < square[:house_cost].to_i
        level = state[:houses][square[:index]].to_i
        return false if level < 4 && available_houses(state) <= 0
        return false if level == 4 && state[:houses].values.count(5) >= state[:board_data].fetch(:bank_hotels)

        state[:houses][square[:index]].to_i == group.map { |property| state[:houses][property[:index]].to_i }.min
      end

      def can_sell_building?(state, player, square)
        return false if square == nil || square[:type] != :property || !same_user?(state[:owners][square[:index]], player)
        group = colour_group_squares(state, square[:group])
        level = state[:houses][square[:index]].to_i
        if hotel_liquidation?(state, square)
          return group.all? { |property| same_user?(state[:owners][property[:index]], player) } &&
            square[:index] == group.select { |property| state[:houses][property[:index]] == 5 }.map { |property| property[:index] }.min
        end
        level > 0 && level == group.map { |property| state[:houses][property[:index]].to_i }.max
      end

      def hotel_liquidation?(state, square)
        square != nil && state[:houses][square[:index]] == 5 && available_houses(state) < 4
      end

      def available_houses(state)
        state[:board_data].fetch(:bank_houses) - state[:houses].values.reject { |level| level == 5 }.sum
      end

      def can_mortgage?(state, player, square)
        return false if square == nil || !same_user?(state[:owners][square[:index]], player) || state[:mortgaged][square[:index]]
        return false if state[:houses][square[:index]].to_i > 0
        return true if square[:type] != :property

        colour_group_squares(state, square[:group]).all? { |property| state[:houses][property[:index]].to_i.zero? }
      end

      def rent_for(state, square, owner)
        if square[:type] == :railroad
          count = owned_squares(state, owner).count { |item| item[:type] == :railroad }
          return money(state, [25, 50, 100, 200, 400, 600].fetch(count - 1))
        end
        if square[:type] == :utility
          utilities = owned_squares(state, owner).count { |item| item[:type] == :utility }
          return state[:last_roll].to_i * money(state, [4, 10, 25, 50].fetch(utilities - 1))
        end
        houses = state[:houses][square[:index]].to_i
        rent = square[:rents][houses]
        rent *= 2 if houses.zero? && owns_group?(state, owner, square[:group])
        rent
      end

      def owned_squares(state, player)
        state[:board].select { |square| same_user?(state[:owners][square[:index]], player) }
      end

      def unmortgage_cost(property)
        # Exact integer ceiling: 100 + 10% must be 110, not Float's 111.
        (property[:mortgage].to_i * 11 + 9) / 10
      end

      def completed_colour_groups(state)
        state[:board].select { |square| square[:type] == :property }.group_by { |square| square[:group] }.filter_map do |group, squares|
          owner = state[:owners][squares.first[:index]]
          [owner, group] if owner && squares.all? { |square| same_user?(state[:owners][square[:index]], owner) }
        end
      end

      def announce_completed_groups(state, previous, event_id, history)
        (completed_colour_groups(state) - previous).each do |owner, group|
          square = state[:board].find { |item| item[:type] == :property && item[:group] == group }
          history << HistoryEntry.new(key: "group_complete:#{event_id}:#{owner}:#{group}",
            text: _("%{player} completed the %{group}.") % { player: participant_name(owner), group: property_group_label(square) },
            event_id: event_id, actor: owner, kind: :game)
        end
      end
    end

    include PropertyManagement
  end
end
