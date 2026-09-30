# The legacy action dialect measures characters, not bytes. Keep its limits
# distinct from native stack byte limits and private payload codecs.
module GameRoomEventProtocol
  MAX_EVENTS = 50
  MAX_ACTION_LENGTH = 32
  MAX_VALUE_LENGTH = 64
  module_function

  def command_value(command, key)
    return command.public_send(key) if command.respond_to?(key)
    return nil if !command.respond_to?(:key?)
    return command[key] if command.key?(key)
    return command[key.to_sym] if command.key?(key.to_sym)
    nil
  end

  def normalized(command)
    { 'action' => command_value(command, 'action').to_s, 'value' => command_value(command, 'value').to_s }
  end

  def validate_commands!(commands)
    if commands.empty? || commands.length > MAX_EVENTS
      raise ArgumentError, 'The game action contains an invalid number of events'
    end
    commands.each do |command|
      action = command_value(command, 'action').to_s
      value = command_value(command, 'value').to_s
      raise ArgumentError, 'A game event requires an action' if action.empty?
      raise ArgumentError, 'The game event action is too long' if action.length > MAX_ACTION_LENGTH
      raise ArgumentError, 'The game event value is too long' if value.length > MAX_VALUE_LENGTH
    end
    commands
  end

  # Incoming wire values are checked independently; do not coerce malformed
  # remote values using the local command adapter.
  def valid_wire_command?(command, move_id: false)
    command.is_a?(Hash) && command['action'].is_a?(String) &&
      command['action'].length.between?(1, MAX_ACTION_LENGTH) &&
      command['value'].is_a?(String) && command['value'].length <= MAX_VALUE_LENGTH &&
      (!move_id || (command['move_id'].is_a?(String) && !command['move_id'].empty?))
  end

  def valid_wire_commands?(commands)
    commands.is_a?(Array) && commands.length.between?(1, MAX_EVENTS) &&
      commands.all? { |command| valid_wire_command?(command, move_id: true) }
  end
end
