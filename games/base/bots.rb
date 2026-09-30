require_relative '../../lib/game_room_localization'

module GameRoomGames
  using GameRoomLocalization::Translations
  class Base
    module Bots
      public

      def supports_bots?
        false
      end

      # Real-time games pace their continuous opponents inside the simulation.
      def supports_bot_move_delay?
        supports_bots?
      end

      def bot_observation(_replay, _actor)
        replay = _replay
        {
          "board" => replay.board,
          "players" => replay.players,
          "current_player" => replay.current_player,
          "winner" => replay.winner,
          "draw" => replay.draw == true,
          "events" => replay.accepted_events.to_a.map do |event|
            {
              "actor" => event["actor"].to_s,
              "action" => event["action"].to_s,
              "value" => event["value"].to_s
            }
          end
        }
      end

      # Games with private hands or answers must return false and provide a safe
      # bot_observation. Tree search then falls back to a non-cheating strategy.
      def perfect_information?
        true
      end

      # Optional local pacing; human actions and network synchronization do not wait.
      def bot_move_delay(replay, _actor, context: nil)
        # Simple board games keep their position in Replay#board and omit state.
        # Their configured delay still comes from the shared action context.
        state = replay.state || {}
        options = context&.options || state[:options] || {}
        delay = [[normalize_options(options)["bot_delay"].to_f, 0.0].max, 5.0].min
        deadline = state[:turn_deadline].to_f
        deadline = state[:deadline].to_f if state[:phase] == :answering
        deadline = state[:auction_deadline].to_f if state[:phase] == :auction
        if deadline > 0
          now = context&.now || GameRoomSessionClock.for_state(state)
          delay = [delay, [deadline - now.to_f - 1.0, 0.0].max].min
        end
        delay
      end

      # This key controls only the local waiting period, never submission or
      # confirmation. Games may ignore events that leave the pending turn intact.
      def bot_delay_revision(_replay, revision)
        revision
      end

      # Opt in only for games with simultaneous or out-of-turn actions.
      # Their normal action_for/replay validation still decides legality.
      def actions_during_bot_turn?
        false
      end

      def bot_action_score(_replay, _actor, _action, context: nil)
        0.0
      end

      def bot_state_key(replay, actor)
        aliases = replay.players.each_with_index.each_with_object({}) do |(player, index), result|
          result[player.to_s.downcase] = same_user?(player, actor) ? "self" : "player:#{index + 1}"
        end
        canonical_json(bot_identity_value(bot_observation(replay, actor), aliases))
      end

      # Search-based games may override this with a compact board encoding.
      def bot_search_key(replay, actor)
        bot_state_key(replay, actor)
      end

      def bot_action_key(action)
        canonical_json(action)
      end

      def bot_allied?(_replay, first, second)
        same_user?(first, second)
      end

      def bot_reward(replay, actor)
        return 0.0 if !replay.finished? || replay.draw
        return 1.0 if same_user?(replay.winner, actor)

        -1.0
      end

      def bot_position_value(replay, actor)
        replay.finished? ? bot_reward(replay, actor) : 0.0
      end

      def bot_strategy
        nil
      end

      protected

      def bot_identity_value(value, aliases)
        case value
        when Hash
          value.each_with_object({}) do |(key, item), result|
            normalized_key = aliases.fetch(key.to_s.downcase, key)
            result[normalized_key] = bot_identity_value(item, aliases)
          end
        when Array
          value.map { |item| bot_identity_value(item, aliases) }
        when String
          aliases.fetch(value.downcase, value)
        else
          value
        end
      end
    end

    include Bots
  end
end
