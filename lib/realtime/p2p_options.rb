# encoding: UTF-8
require_relative '../game_room_localization'

module GameRoomRealtime
  # Use ELTEN's native full-P2P mode and its relay fallback. No additional
  # sockets, forwarding authority or changes to reliable event ordering.
  module P2POptions
    DEFAULT_LIMIT = 8
    LIMIT_RANGE = (0..0x7fffffff).freeze

    def self.limit(values)
      raw = values.fetch('p2p_participants_limit') { values.fetch(:p2p_participants_limit, DEFAULT_LIMIT) }
      Integer(raw.to_s, 10)
    rescue ArgumentError
      -1 # An invalid edit must not silently become unlimited or the default.
    end

    def self.session_options(values)
      values = {} unless values.is_a?(Hash)
      enabled = values.fetch('p2p_enabled') { values[:p2p_enabled] }
      return {}.freeze unless enabled == true || enabled.to_s == '1' || enabled.to_s.downcase == 'true'
      count = limit(values)
      raise ArgumentError, 'Invalid P2P participant limit' unless LIMIT_RANGE.cover?(count)
      { p2p: :full, p2p_participants_limit: count }.freeze
    end

    # Opt-in only for games using the shared Communications channel.
    module GameOptions
      using GameRoomLocalization::Translations

      def p2p_option_definitions
        [
          GameRoomGames::OptionDefinition.new(key: 'p2p_enabled',
            label: _('Full P2P (direct connections between participants)'), summary_label: _('Full P2P'),
            kind: :boolean, default: false),
          GameRoomGames::OptionDefinition.new(key: 'p2p_participants_limit',
            label: _('P2P participant limit (0 for unlimited)'), summary_label: _('P2P participant limit'),
            kind: :integer, default: DEFAULT_LIMIT, visible_if: { 'p2p_enabled' => true })
        ]
      end

      def normalize_options(values)
        normalized = super
        normalized['p2p_participants_limit'] = P2POptions.limit(values.is_a?(Hash) ? values : {})
        normalized
      end

      def validation_error(options, player_count: nil)
        error = super
        return error if error
        values = normalize_options(options)
        if values['p2p_enabled'] && !LIMIT_RANGE.cover?(values['p2p_participants_limit'])
          _('Enter a valid non-negative whole-number P2P participant limit (0 for unlimited).')
        end
      end
    end
  end
end
