require_relative "specifications"
require_relative "../game_room_localization"

module GameSurfaces
  using GameRoomLocalization::Translations



  class DiceTray
    include ActionEmitter

    def initialize(spec, state: {})
      @spec = spec
      @dice = @spec.dice.to_a
      validate_dice!
      validate_commands!
      index = state_value(state, "index", 0)
      @list = RefreshAwareListBox.new(
        @dice.each_with_index.map { |die, position| die_label(die, position) },
        header: @spec.header.to_s,
        index: bounded_index(index),
        quiet: true,
        empty_label: (@spec.empty_label || _("No dice")).to_s
      )
      @list.on(:select) do |params|
        selected_index = params.to_a[0].to_i
        die = @dice[selected_index]
        next if die == nil || die.enabled == false

        emit_action(
          "dice",
          "toggle",
          {
            "tray_id" => @spec.id.to_s,
            "die_id" => die.id.to_s,
            "index" => selected_index,
            "value" => die.value,
            "sides" => die.sides.to_i,
            "held" => die.held == true
          }
        )
      end

      @buttons = @spec.commands.to_a.select { |command| command.enabled != false }.map do |command|
        button = Button.new(command.label.to_s)
        button.on(:press) do
          emit_action(
            "dice",
            command.id,
            (command.payload == nil ? {} : command.payload.to_h).merge("tray_id" => @spec.id.to_s)
          )
        end
        button
      end
    end

    def fields
      [@list] + @buttons
    end

    def state
      { "index" => @list.index.to_i }
    end

    private

    def validate_dice!
      ids = @dice.map { |die| die.id.to_s }
      raise ArgumentError, "die ids must not be empty" if ids.any?(&:empty?)
      raise ArgumentError, "die ids must be unique" if ids.uniq.length != ids.length
      @dice.each do |die|
        sides = die.sides.to_i
        raise ArgumentError, "a die requires at least two sides" if sides < 2
        next if die.value == nil

        value = die.value.to_i
        raise ArgumentError, "die value is outside its range" if !value.between?(1, sides)
      end
    end

    def validate_commands!
      commands = @spec.commands.to_a
      ids = commands.map { |command| command.id.to_s }
      raise ArgumentError, "dice command ids must not be empty" if ids.any?(&:empty?)
      raise ArgumentError, "dice command ids must be unique" if ids.uniq.length != ids.length
      if commands.any? { |command| !command.payload.nil? && !command.payload.respond_to?(:to_h) }
        raise ArgumentError, "dice command payloads must be hashes"
      end
    end

    def die_label(die, position)
      return die.label.to_s if die.label != nil && !die.label.to_s.empty?

      value = if die.value == nil
        _("not rolled")
      else
        die.value.to_i.to_s
      end
      status = die.held == true ? _("held") : _("available")
      _("Die %{number}: %{value}; %{sides} sides; %{status}") % {
        number: position + 1,
        value: value,
        sides: die.sides.to_i,
        status: status
      }
    end

    def bounded_index(index)
      return 0 if @dice.empty?

      [[index.to_i, 0].max, @dice.length - 1].min
    end

    def state_value(state, key, default)
      GameSurfaces::StateReader.integer(state, key, default)
    end
  end
end
