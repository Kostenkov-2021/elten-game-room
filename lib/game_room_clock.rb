require "thread"
require_relative "network_errors"

# ELTEN 3.0.4 owns synchronization, monotonic time, retry and account changes.
# This adapter only keeps the game's Numeric clock/error contract. No read
# starts HTTP, waits for a sample or accesses the host's private lifecycle.
module GameRoomClock
  CLOCK_LOCK = Mutex.new
  class Clock
    def initialize(source: nil, wall: -> { Time.now.to_f })
      @source, @wall = source, wall
    end

    def now
      native = source
      return @wall.call.to_f unless native # Standalone rules/tools only.

      sample = native.now
      value = sample.to_f if sample.is_a?(Time) || sample.is_a?(Numeric)
      unless value && value.finite? && value > 0
        raise GameRoomNetworkErrors::ClockUnavailable, "Server clock is not synchronized"
      end
      value
    end

    alias synchronize now

    def synchronized?
      !!source&.synchronized?
    end

    def server_available?
      source != nil
    end

    private

    def source
      @source || (EltenAPI::ServerClock if defined?(EltenAPI::ServerClock))
    end
  end

  class << self
    def clock
      return @clock if @clock
      CLOCK_LOCK.synchronize { @clock ||= Clock.new }
    end

    def server_available?; clock.server_available?; end
    def synchronize; clock.synchronize; end
    def now; clock.now; end
    def synchronized?; clock.synchronized?; end
  end
end
