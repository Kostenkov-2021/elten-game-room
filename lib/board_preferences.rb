# Only presentation choices belong here, never a cursor, selection or player ID.
class GameRoomBoardPreferences
  PATH = "board-presentation.json".freeze
  FIELDS = {"chess" => {"orientation_flipped" => [true, false]},
    "checkers" => {"orientation_flipped" => [true, false], "coordinate_label_set" => %w[numeric algebraic]},
    "ludo" => {"player_labels" => %w[names colours]}}.freeze

  def initialize(storage, game_id)
    @storage, @game_id = storage, game_id
    @values = {}
    @values = clean(@storage.read_json(PATH, default: {}).to_h[@game_id]) if FIELDS.key?(@game_id) && @storage.respond_to?(:read_json)
  rescue StandardError
    @values = {}
  end

  def values
    @values.dup
  end

  def restore(spec, state)
    result = state.dup
    if FIELDS.fetch(@game_id, {}).key?("orientation_flipped") && spec.respond_to?(:default_orientation)
      normal = spec.default_orientation || "normal"
      result["orientation"] = @values["orientation_flipped"] ? (normal == "rotated" ? "normal" : "rotated") : normal
    end
    %w[coordinate_label_set player_labels].each { |key| result[key] = @values[key] if @values.key?(key) }
    result
  end

  def remember(command, spec, state)
    next_values = @values.dup
    case command.to_s
    when "toggle_orientation"
      next_values["orientation_flipped"] = state["orientation"] != (spec.default_orientation || "normal")
    when "toggle_coordinate_labels"
      next_values["coordinate_label_set"] = state["coordinate_label_set"]
    when "toggle_player_labels"
      next_values["player_labels"] = state["player_labels"]
    else
      return false
    end
    next_values = clean(next_values)
    return false if next_values == @values
    @values = next_values
    if @storage.respond_to?(:update_json)
      @storage.update_json(PATH, default: {}) do |data|
        raise IOError, "Invalid board preferences" unless data.is_a?(Hash)
        data[@game_id] = @values.dup
      end
    end
    true
  rescue StandardError => error
    begin
      Log.warning("Game Room board preference could not be saved: #{error.class}") if defined?(Log)
    rescue StandardError
      nil
    end
    true # Keep the local choice even if persistence failed; never stop a game.
  end

  private

  def clean(values)
    return {} unless values.is_a?(Hash)
    FIELDS.fetch(@game_id, {}).each_with_object({}) do |(key, allowed), result|
      result[key] = values[key] if allowed.include?(values[key])
    end
  end
end
