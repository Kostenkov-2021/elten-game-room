# encoding: UTF-8
module GameRoomPong
  # Personal values only. Never included in a table's rules or sent as audio
  # settings to another player. The program caches the normalized local file.
  module Preferences
    DEFAULTS = { 'auto_return' => false, 'own_volume' => 100,
      'opponent_volume' => 100, 'announcer_volume' => 100, 'doubles_sounds' => 'seats' }.freeze
    module_function

    def normalize(values)
      values = values.is_a?(Hash) ? values : {}
      DEFAULTS.to_h do |key, fallback|
        value = values[key]
        normalized = if key == 'doubles_sounds'
          %w[seats personal].include?(value) ? value : fallback
        elsif key == 'auto_return'
          value == true
        else
          value.is_a?(Integer) ? value.clamp(0, 200) : fallback
        end
        [key, normalized]
      end
    end

    def read(program)
      return DEFAULTS unless program.respond_to?(:pong_preferences, true)
      program.send(:pong_preferences)
    end
  end
end
