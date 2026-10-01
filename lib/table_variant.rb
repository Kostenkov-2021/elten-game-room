require "json"
require_relative "game_content"

# Both kinds of notification carry a small semantic snapshot. Rendering is
# local to the recipient; no table lookup, normalization to missing defaults,
# private options or sender-language sentences are needed.
module GameRoomTableVariant
  module_function

  def options_for(game, options)
    return {} unless game && options.is_a?(Hash)
    game.notification_option_keys(options).each_with_object({}) do |key, result|
      next if key.start_with?("__") || !options.key?(key)
      value = options[key]
      next unless [true, false].include?(value) || value.is_a?(Integer) ||
        (value.is_a?(String) && value.bytesize <= 128 && value.valid_encoding?)
      result[key] = value
    end
  end

  def payload(game, serialized)
    source = serialized.is_a?(Hash) ? serialized : JSON.parse(serialized.to_s)
    {"format" => 1, "options" => options_for(game, source)}
  rescue JSON::ParserError
    {"format" => 1, "options" => {}}
  end

  def text(game, payload)
    return "" unless game && payload.is_a?(Hash) && payload["format"] == 1
    options = options_for(game, payload["options"])
    return "" if options.empty?
    GameRoomContent.utf8(game.notification_variant(options))
  end
end
