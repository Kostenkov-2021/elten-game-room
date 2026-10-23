require_relative '../../lib/game_room_localization'

module GameRoomGames
  using GameRoomLocalization::Translations
  class Monopoly
    module Debt
      private

      def apply_bankruptcy(state, event, actor, repository, history)
        player = player_key(state, actor)
        return false if !same_user?(state[:current_player], actor) || state[:cash][player] >= 0
        settle_debts(state, repository.event_id(event), history)
        creditor = (state[:debts][player] || []).find { |debt| state[:players].include?(debt[:to]) && !state[:bankrupt][debt[:to]] }&.fetch(:to)
        state[:bankrupt][player] = true
        state[:owners].keys.each do |index|
          next if !same_user?(state[:owners][index], player)
          if creditor
            state[:owners][index] = creditor
            buildings = state[:houses][index].to_i
            state[:cash][creditor] += (buildings == 5 ? 5 : buildings) * state[:board][index][:house_cost].to_i / 2
          else
            state[:owners].delete(index)
            state[:mortgaged].delete(index)
          end
          state[:houses].delete(index)
        end
        held = state[:held_jail_cards].delete(player).to_a
        if creditor
          state[:jail_cards][creditor] += state[:jail_cards][player]
          (state[:held_jail_cards][creditor] ||= []).concat(held)
        else
          held.each { |deck, card| state[:card_decks][deck] << card }
        end
        state[:jail_cards][player] = 0
        state[:cash][player] = 0
        state[:debts].delete(player)
        state[:extra_turn] = false
        state[:doubles] = 0
        id = repository.event_id(event)
        text = creditor ? _("%{player} declared bankruptcy. Remaining property goes to %{creditor}.") % { player: participant_name(player), creditor: participant_name(creditor) } : _("%{player} declared bankruptcy. Remaining property returns to the bank.") % { player: participant_name(player) }
        history << HistoryEntry.new(key: "bankrupt:#{id}", text: text, event_id: id, actor: actor, kind: :game)
        remaining = active_players(state)
        if remaining.length == 1
          state[:winner] = remaining.first
          state[:current_player] = nil
          state[:phase] = :finished
          history << result_history(event_id: id, winner: state[:winner])
        else
          state[:turn_number] += 1
          state[:current_player] = next_active_player(state, player)
          state[:phase] = :awaiting_roll
        end
        true
      end

      def unaffordable_purchase?(state)
        return false if state[:phase] != :property_decision || state[:current_player] == nil
        player = player_key(state, state[:current_player])
        square = current_square(state, player)
        square != nil && state[:owners][square[:index]] == nil && state[:cash][player] < square[:price].to_i
      end

      def unavoidable_bankruptcy?(state)
        return false if state[:winner] || ![:awaiting_roll, :turn_complete].include?(state[:phase])
        player = player_key(state, state[:current_player])
        return false if player == nil || state[:bankrupt][player] || state[:cash][player] >= 0
        management_actions(state, player).none? { |action| %w[sell mortgage].include?(action["action"]) }
      end

      def apply_automatic_bankruptcy(state, event, actor, repository, history)
        return false if !same_user?(actor, state[:players].first) || !unavoidable_bankruptcy?(state)
        index, turn = event["value"].to_s.split("|", 2).map { |value| Integer(value, 10) }
        return false if turn != state[:turn_number] || index != player_index(state[:players], state[:current_player])
        apply_bankruptcy(state, event, state[:current_player], repository, history)
      rescue ArgumentError, TypeError
        false
      end

      def bank_recipient(state)
        state[:options]["free_parking_jackpot"] ? :jackpot : :bank
      end

      def recipient_name(recipient)
        return _("the bank") if recipient == :bank
        return _("the Free Parking pool") if recipient == :jackpot
        participant_name(recipient)
      end

      # Describe the existing transfer, including its unpaid part. Keep the
      # accounting in pay_money, shared with simulations and debt settlement.
      def pay_and_describe(state, player, recipient, amount, reason)
        amount = [amount.to_i, 0].max
        paid = [[state[:cash][player], 0].max, amount].min
        pay_money(state, player, recipient, amount)
        text = if recipient == :jackpot
          _("%{player} pays %{amount} into the Free Parking pool: %{reason}.") % {
            player: participant_name(player), amount: paid, reason: reason
          }
        elsif state[:players].include?(recipient)
          _("%{player} pays %{recipient} %{amount}: %{reason}.") % {
            player: participant_name(player), recipient: participant_name(recipient), amount: paid, reason: reason
          }
        else
          _("%{player} paid %{amount} to %{recipient}: %{reason}.") % {
            player: participant_name(player), amount: paid, recipient: recipient_name(recipient), reason: reason
          }
        end
        if paid < amount
          text += " " + _("%{player} still owes %{amount} to %{recipient}.") % { player: participant_name(player), amount: amount - paid, recipient: recipient_name(recipient) }
        end
        text
      end

      def pay_money(state, player, recipient, amount)
        amount = [amount.to_i, 0].max
        paid = [[state[:cash][player], 0].max, amount].min
        state[:cash][player] -= amount
        credit_money(state, recipient, paid)
        if paid < amount
          (state[:debts][player] ||= []) << { to: recipient, amount: amount - paid }
        end
      end

      def credit_money(state, recipient, amount)
        if recipient == :jackpot
          state[:jackpot] += amount
        elsif state[:players].include?(recipient) && !state[:bankrupt][recipient]
          state[:cash][recipient] += amount
        end
      end

      def settle_debts(state, event_id = nil, history = nil)
        seen = {}
        loop do
          claims = state[:debts].flat_map { |player, debts| debts.map { |debt| [player, debt] } }
          break if claims.empty?
          amounts = claims.map { |_, debt| debt[:amount] }
          # At a complete-pass boundary this vector determines all following
          # payments until a claim is exhausted. Keep raw (not clipped) funds:
          # negative funds and creditor order must not be lost by netting debts.
          funds = state[:players].map do |player|
            state[:cash][player] + state[:debts].fetch(player, []).sum { |debt| debt[:amount] }
          end
          previous = seen[funds]
          if previous && settle_repeated_debt_cycle(state, claims, previous, amounts, event_id, history)
            state[:debts].each_value { |debts| debts.reject! { |debt| debt[:amount] <= 0 } }
            seen.clear
            next
          end
          seen[funds] = amounts
          paid_any = false
          removed_any = false
          state[:debts].each do |player, debts|
            available = [state[:cash][player] + debts.sum { |debt| debt[:amount] }, 0].max
            debts.each do |debt|
              paid = [available, debt[:amount]].min
              next if paid <= 0
              available -= paid
              repay_debt(state, player, debt, paid, event_id, history)
              paid_any = true
            end
            removed_any = true if debts.reject! { |debt| debt[:amount] <= 0 }
          end
          break if !paid_any
          # A later creditor can start receiving money after an earlier debt
          # disappears. Never reuse a cycle across this change of topology.
          seen.clear if removed_any
        end
      end

      def settle_repeated_debt_cycle(state, claims, previous, amounts, event_id, history)
        reductions = previous.zip(amounts).map { |before, after| before - after }
        repeats = reductions.each_with_index.filter_map do |reduction, index|
          amounts[index] / reduction if reduction > 0
        end.min
        return false if repeats == nil || repeats <= 0
        # The sampled cycle has already happened. Repeat only whole cycles
        # that fit every remaining claim; condense their repeated repayments
        # instead of creating amount-proportional history and replay work.
        claims.each_with_index do |(player, debt), index|
          paid = reductions[index] * repeats
          repay_debt(state, player, debt, paid, event_id, history) if paid > 0
        end
        true
      end

      def repay_debt(state, player, debt, paid, event_id, history)
        debt[:amount] -= paid
        credit_money(state, debt[:to], paid)
        return if history == nil
        text = _("%{player} repays %{amount} of debt to %{recipient}.") % { player: participant_name(player), amount: paid, recipient: recipient_name(debt[:to]) }
        if debt[:amount] > 0
          text += " " + _("%{player} still owes %{amount} to %{recipient}.") % { player: participant_name(player), amount: debt[:amount], recipient: recipient_name(debt[:to]) }
        end
        history << HistoryEntry.new(key: "debt:#{event_id}:#{history.length}", text: text, event_id: event_id, actor: player, kind: :game)
      end
    end

    include Debt
  end
end
