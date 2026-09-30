require_relative "specifications"
module GameSurfaces



  class CommandPanel
    include ActionEmitter

    def initialize(spec, state: {})
      @spec = spec
      commands = @spec.commands.to_a
      ids = commands.map { |command| command.id.to_s }
      raise ArgumentError, "command ids must not be empty" if ids.any?(&:empty?)
      raise ArgumentError, "command ids must be unique" if ids.uniq.length != ids.length
      raise ArgumentError, "command payloads must be hashes" if commands.any? { |command| !command.payload.nil? && !command.payload.respond_to?(:to_h) }

      @commands = commands.select { |command| command.enabled != false }
      raise ArgumentError, "a command panel requires an enabled command" if @commands.empty?

      @controls = @commands.map do |command|
        button = Button.new(command.label.to_s)
        button.on(:press) do
          emit_action("command", command.id, command.payload == nil ? {} : command.payload.to_h)
        end
        button
      end
    end

    def fields
      @controls
    end

    def state
      {}
    end
  end
end
