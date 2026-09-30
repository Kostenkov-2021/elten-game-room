# Only presentation choices belong here, never a cursor, selection or player ID.
class GameRoomBoardPreferences
  PATH = "board-presentation.json".freeze
  def initialize(storage, game)
    @storage, @game_id = storage, game.id
    @definitions = game.board_preference_definitions
    @values = {}
    @values = clean(@storage.read_json(PATH, default: {}).to_h[@game_id]) if !@definitions.empty? && @storage.respond_to?(:read_json)
  rescue StandardError
    @values = {}
  end

  def values
    @values.dup
  end

  def restore(spec, state)
    result = state.dup
    @definitions.each { |definition| definition.restore(spec, @values[definition.key], result) }
    result
  end

  def remember(command, spec, state)
    next_values = @values.dup
    definition = @definitions.find { |item| item.command == command.to_s }
    return false unless definition
    next_values[definition.key] = definition.read(spec, state)
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
    @definitions.each_with_object({}) do |definition, result|
      key = definition.key
      result[key] = values[key] if definition.values.include?(values[key])
    end
  end
end
