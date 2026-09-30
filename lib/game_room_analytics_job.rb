require "thread"
require_relative "network_errors"

# Memory-only scheduling on the existing extension tick. The native managed
# task executes one finite batch; no polling thread, sleeps or overlapping jobs.
class GameRoomAnalyticsJob
  RETRIES = [30, 60, 120, 300].freeze
  class Cancelled < StandardError; end

  class Token
    def initialize(native, valid)
      @native, @valid = native, valid
    end

    def cancelled?
      !@valid.call || (@native && @native.respond_to?(:cancelled?) && @native.cancelled?)
    end

    def raise_if_cancelled!
      raise Cancelled, "Analytics context ended" unless @valid.call
      @native&.raise_if_cancelled!
    end

    def on_cancel(&callback)
      @native.on_cancel(&callback) if @native&.respond_to?(:on_cancel)
    end
  end

  def initialize(trigger:, enabled: -> { true }, delay: 0, heartbeat: nil,
    persist_during_retry: false, last_error: nil, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, &operation)
    @trigger, @enabled, @operation = trigger, enabled, operation
    @delay, @heartbeat, @persist_during_retry, @clock = delay, heartbeat, persist_during_retry, clock
    @last_error = last_error
    @lock, @failures = Mutex.new, 0
    @closed = @blocked = @running = @queued = false
  end

  def request
    @lock.synchronize do
      return if @closed || @blocked
      due = @clock.call + @delay
      @requested_at = [@requested_at, due].compact.min
    end
    tick
  end

  def tick
    return unless @enabled.call
    trigger = @lock.synchronize do
      due = due_at
      next false if @closed || @blocked || @queued || @running || !due || due > @clock.call
      @queued = true
    end
    return unless trigger
    begin
      accepted = @trigger.call
      @lock.synchronize { @queued = false } if accepted == false || [:inactive, :running, :not_due].include?(accepted)
    rescue StandardError
      @lock.synchronize { @queued = false }
      raise
    end
  end

  def run(native_token = nil)
    upload = @lock.synchronize do
      @queued = false
      return if @closed || @blocked || @running || !@enabled.call
      due = due_at
      return unless due && due <= @clock.call
      @running = true
      @requested_at = @next_at = nil
      !@retry_at || @clock.call >= @retry_at
    end
    token = Token.new(native_token, -> { !@closed && @enabled.call })
    status = @operation.call(token, upload)
    token.raise_if_cancelled!
    @lock.synchronize do
      now = @clock.call
      case status
      when :retry
        delay = RETRIES[[@failures, RETRIES.length - 1].min]
        error = @last_error&.call
        delay = GameRoomNetworkErrors.retry_delay(error, normal: delay, rate_limit: delay) if error
        @retry_at = now + delay
        @failures += 1
        @next_at = @retry_at
      when :waiting
        @next_at = @retry_at
      when :persist_more
        @next_at = now
      when :blocked
        @blocked = true
        @next_at = @requested_at = nil
      when :unchanged
        @next_at = @heartbeat_at
      else
        @failures, @retry_at = 0, nil
        @next_at = now if status == :more
        @heartbeat_at = status == :active && @heartbeat ? now + @heartbeat : nil
        @next_at = @heartbeat_at if @heartbeat_at
      end
    end
    status
  rescue Cancelled
    @lock.synchronize { @requested_at ||= @clock.call unless @closed }
    nil
  rescue StandardError => error
    @lock.synchronize { @blocked = true; @requested_at = @next_at = nil }
    Log.warning("Game Room analytics job failed: #{error.class}") if defined?(Log)
    nil
  ensure
    @lock.synchronize { @running = false } if upload != nil
  end

  def close
    @lock.synchronize { @closed = true; @requested_at = @next_at = nil }
  end

  private

  def due_at
    due = [@requested_at, @next_at].compact.min
    due = [due, @retry_at].max if due && @retry_at && !@persist_during_retry
    due
  end
end
