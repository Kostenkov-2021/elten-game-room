require_relative '../host_bridge'
require 'weakref'

module GameRoomAudioBall
  module Keyboard
    KEYS = {0x26 => 'up', 0x57 => 'up', 0x25 => 'left', 0x44 => 'left',
      0x28 => 'down', 0x53 => 'down', 0x27 => 'prepare', 0x41 => 'prepare'}.freeze
    MODIFIERS = [0x10, 0x11, 0x12, 0x5B, 0x5C, 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5].freeze
    FRAME = :@game_room_audio_ball_presses
    MAX_PRESSES = 32
    MAX_CHANGES = MAX_PRESSES * 2

    # Relevant controls only, attached to one native result; never a key log.
    class Frame < Array
      attr_reader :held, :changes, :reset

      def initialize(presses, held, changes: [], reset: false)
        super(presses)
        @held = held.freeze
        @changes, @reset = changes.freeze, reset
        freeze
      end
    end

    module_function

    def install
      return unless defined?(EltenAPI::KeyboardState)
      target = EltenAPI::KeyboardState.singleton_class
      bridge = installed_bridge(target)
      previous = bridge && bridge.instance_variable_get(:@game_room_audio_ball_keyboard_observer)
      return if previous.equal?(self)

      # The host singleton outlives the application namespace. Rebind the
      # same module on upgrade, including the old boolean-marker bridge;
      # otherwise its closure keeps returning the previous app's metadata.
      @suppressed = (previous && previous.instance_variable_get(:@suppressed) || {}).dup
      previous = nil # The replacement closures must not retain the retired namespace.
      bridge ||= Module.new

      observer = self
      bridge.module_eval do
        define_method(:update) do |*args, **options, &block|
          return super(*args, **options, &block) unless observer.active?
          modifiers = MODIFIERS.each_with_object({}) { |key, held| held[key] = held?(key) }
          previous = KEYS.keys.each_with_object({}) { |key, held| held[key] = held?(key) }
          result = super(*args, **options, &block)
          observer.capture(result, options, previous, modifiers)
          result
        end

        define_method(:suppress_held_until_release) do |*args, **options, &block|
          return super(*args, **options, &block) unless observer.active?
          blocked = KEYS.keys.select { |key| held?(key) }
          result = super(*args, **options, &block)
          observer.suppress(blocked)
          result
        end

        define_method(:reset) do |*args, **options, &block|
          result = super(*args, **options, &block)
          observer.reset
          result
        end
      end
      target.prepend(bridge) unless target.ancestors.include?(bridge)
      bridge.instance_variable_set(:@game_room_audio_ball_keyboard_observer, observer)
      target.instance_variable_set(:@game_room_audio_ball_keyboard_bridge, bridge)
      # Do not replay input/metadata from before the replacement, nor reset
      # the host's keyboard state or other applications' controls.
      suppress(KEYS.keys.select { |code| EltenAPI::KeyboardState.held?(code) })
    end

    def installed_bridge(target)
      GameRoomHostBridge.locate(target, marker: :@game_room_audio_ball_keyboard_bridge,
        method_name: :update, source: '/lib/audio_ball/keyboard.rb')
    end

    def capture(result, options, previous, modifiers)
      events = options[:events]
      return if result.frozen? || !result.respond_to?(:pressed) || !events.is_a?(Array)
      return if options[:active] == false || !result.equal?(EltenAPI::KeyboardState.current)
      return if defined?(EltenWindow) && EltenWindow.respond_to?(:keyboard_flags_driven?) && EltenWindow.keyboard_flags_driven?

      presses, released, mentioned, changes = [], {}, [], []
      reset = false
      blocked = (@suppressed || {}).dup
      down = previous.dup
      events.each do |code, state, press_state|
        code = code.to_i
        modifiers[code] = [true, :repeat, :held].include?(state) if MODIFIERS.include?(code)
        next unless KEYS.key?(code)
        mentioned << code unless mentioned.include?(code)
        if state == false
          down[code] = false
          released[code] = true
          blocked.delete(code)
          changes << [code, false, false].freeze
        elsif state == true
          fresh = !down[code]
          down[code] = true
          next unless fresh && !blocked[code]
          modified = press_state != nil ? modifiers_in?(press_state) : modifiers.value?(true)
          presses.shift if presses.length == MAX_PRESSES
          presses << [code, modified, released.key?(code)].freeze
          changes << [code, true, modified].freeze
        elsif state == :repeat || state == :held
          down[code] = true
        end
        if changes.length > MAX_CHANGES
          changes.shift
          reset = true
        end
      end

      # Raw/synthetic input has no chronology. Keep the unambiguous fallback,
      # but do not guess where it belongs among multiple physical presses.
      missing = KEYS.keys.select { |code| result.pressed[code] && !previous[code] && !blocked[code] } - mentioned
      unless missing.empty?
        if presses.empty? && missing.length == 1
          code = missing.first
          state = result.press_states[code]
          modified = state ? MODIFIERS.any? { |key| state[key] } : modifiers.value?(true)
          presses << [code, modified, false].freeze
          changes << [code, true, modified].freeze
        else
          presses.clear
          changes.clear
          reset = true
        end
      end
      if changes.length > MAX_CHANGES
        changes.shift
        reset = true
      end
      raw = options[:raw_state].to_s
      @suppressed = blocked.select { |key, _| (raw.getbyte(key).to_i & 0x80) != 0 }
      result.instance_variable_set(FRAME, Frame.new(presses,
        KEYS.keys.select { |code| result.held[code] }, changes: changes, reset: reset))
    rescue StandardError
      nil
    end

    def modifiers_in?(state)
      MODIFIERS.any? { |key| (state.to_s.getbyte(key).to_i & 0x80) != 0 }
    end

    def active?
      @active_field && @active_field.weakref_alive?
    end

    def activate(field)
      return unless defined?(EltenAPI::KeyboardState)
      install
      return if active? && @active_field.__getobj__.equal?(field)
      @active_field = WeakRef.new(field)
      @suppressed = {}
      suppress(KEYS.keys.select { |code| EltenAPI::KeyboardState.held?(code) })
    end

    def deactivate(field)
      return unless active? && @active_field.__getobj__.equal?(field)
      @active_field = nil
      @suppressed = {}
      result = EltenAPI::KeyboardState.current
      result.remove_instance_variable(FRAME) if !result.frozen? && result.instance_variable_defined?(FRAME)
    end

    def suppress(keys)
      @suppressed ||= {}
      keys.each { |code| @suppressed[code] = true }
      result = EltenAPI::KeyboardState.current
      result.instance_variable_set(FRAME, Frame.new([], KEYS.keys.select { |code| result.held[code] }, reset: true)) unless result.frozen?
    end

    def reset
      @suppressed = {}
    end

    def frame
      return unless defined?(EltenAPI::KeyboardState)
      return unless active?
      value = EltenAPI::KeyboardState.current.instance_variable_get(FRAME)
      value if value.is_a?(Frame)
    end
  end
end
