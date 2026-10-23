require_relative 'assertions'

module GameRoomTest
  class Cases
    include Assertions

    def initialize; @cleanups = []; end

    def run(name)
      body_failed = false
      begin
        yield self
      rescue Exception
        # Track this body, not $!, which may belong to a caller's rescue.
        # Preserve every original exception, including non-StandardError exits.
        body_failed = true
        raise
      ensure
        cleanup_error = cleanup_all
        raise cleanup_error if cleanup_error && !body_failed
      end
      puts "PASS #{name}"
    rescue StandardError => error
      warn "FAIL #{name}: #{error.class}: #{error.message}"
      raise
    end

    def cleanup(&block); @cleanups << block; end

    private

    def cleanup_all
      cleanups, @cleanups = @cleanups, []
      first_error = nil
      cleanups.reverse_each do |cleanup|
        begin
          cleanup.call
        rescue StandardError => error
          first_error ||= error
          warn "Cleanup failed: #{error.class}: #{error.message}\n#{Array(error.backtrace).join("\n")}"
        end
      end
      first_error
    end
  end

  class Clock
    def initialize(now = 0.0); @now = now; end
    def call; @now; end
    def advance(seconds); @now += seconds; end
  end
end
