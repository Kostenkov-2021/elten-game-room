require_relative 'keyboard'

module GameRoomAudioBall
  # Local defence only. Restoring a held key never creates an attack command.
  class DefenseInput
    attr_reader :lane

    def initialize
      reset
    end

    def reset
      @flight = @lane = @generation = nil
      @held = []
    end

    def forget_held
      @held.clear
    end

    def update(flight:, enabled:, input:, commands:)
      if flight != @flight
        reset
        @flight = flight
      end
      unless enabled && flight
        forget_held
        return @lane
      end
      unless input
        forget_held
        # Command-only callers keep the original short-press behaviour.
        @lane = commands.reverse.find { |command| %w[up left down].include?(command) } || @lane
        return @lane
      end
      forget_held if input[:reset] || input[:generation] != @generation
      @generation = input[:generation]
      input[:changes].each do |code, down, modified|
        lane = Keyboard::KEYS[code]
        next unless lane && lane != 'prepare'
        if modified
          forget_held
        elsif down
          @held.delete(code)
          @held << code
          @lane = lane
        else
          @held.delete(code)
          @lane = Keyboard::KEYS.fetch(@held.last) unless @held.empty?
        end
      end
      # Reconcile only releases with this same native snapshot. A held state
      # alone must never arm a key from before this flight or outside the field.
      @held.select! { |code| input[:held].include?(code) }
      @lane = Keyboard::KEYS.fetch(@held.last) unless @held.empty?
      @lane
    end
  end
end
