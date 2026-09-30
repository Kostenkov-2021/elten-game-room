module GameRoomRealtime
  # ELTEN owns the timer lifecycle and monotonic scheduling. A zero-interval
  # native timer lets the match's injected clock retain its immediate first
  # frame and start-to-start cadence, without catching up missed frames.
  class Timer < EltenAPI::Controls::FormTimer
    def initialize(clock:, interval: 0.008, &block)
      super(0, repeat: true) do
        now = clock.call
        if @due == nil || now >= @due
          @due = now + interval
          block.call
        end
      end
    end

    def stop
      @due = nil
      super
    end
  end
end
