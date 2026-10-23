require_relative "network_errors"

module GameRoomSync
  ERROR_BACKOFF = 30.0
  RATE_LIMIT_BACKOFF = 60.0

  Event = Struct.new(:kind, :session_id, :received_at, keyword_init: true)

  class Controller
    attr_reader :table_id, :session_id, :next_reconcile_at

    def initialize(
      transport:,
      table_id:,
      session_id: 0,
      reconnect: nil,
      clock: nil,
      error_backoff: ERROR_BACKOFF,
      rate_limit_backoff: RATE_LIMIT_BACKOFF
    )
      @transport = transport
      @table_id = positive_identifier(table_id)
      raise ArgumentError, "a synchronizer requires a positive table id" if @table_id <= 0

      @session_id = positive_identifier(session_id)
      @error_backoff = positive_duration(error_backoff, "error_backoff")
      @rate_limit_backoff = positive_duration(rate_limit_backoff, "rate_limit_backoff")
      @reconnect = reconnect
      @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      synchronized!
      # Reopening a screen must not strand a pending reveal whose local
      # hidden envelope was already consumed. The store outlives the screen.
      error = @transport.pending_move_error(@table_id) if @transport.respond_to?(:pending_move_error)
      failed!(error) if error != nil
    end

    def update_session(session_id, discard_pending: false)
      @session_id = positive_identifier(session_id)
      consume_game_change if discard_pending && @session_id > 0
      self
    end

    def next_event(allow_recovery: true)
      # LiveSessions delivery must not depend on the host keyboard state. A
      # missed key-release can otherwise strand every following update until
      # the user changes scenes. The shared layout keeps the active edit
      # control, and resume_for_refresh avoids the extra input update which
      # used to consume a queued character during maintenance refreshes.
      recovery = @transport.consume_recovery(@table_id) if @transport.respond_to?(:consume_recovery)
      if recovery == :closed
        synchronized!
        return Event.new(kind: :closed, session_id: @session_id)
      end
      if recovery
        recovery.is_a?(Exception) ? failed!(recovery) : request_recovery!
      end

      # Coalesce notifications during an actual outage. Neither a new gap nor
      # a room/chat wake-up may bypass Retry-After and trigger another read.
      return nil if waiting?
      if @recovery_pending && allow_recovery
        @recovery_pending = false
        @recovering = true
        return Event.new(kind: :recovery, session_id: @session_id)
      end

      started_session_id = @transport.consume_game_start(@table_id)
      if started_session_id != nil && started_session_id.to_i > 0 && started_session_id.to_i != @session_id
        return Event.new(kind: :game_started, session_id: started_session_id.to_i)
      end

      if @session_id > 0
        received_at = consume_game_change
        if received_at != nil && received_at != false
          return Event.new(kind: :game_changed, session_id: @session_id, received_at: received_at)
        end
      end

      if @transport.consume_table_change(@table_id)
        return Event.new(kind: :table_changed, session_id: @session_id)
      end

      nil
    end

    def synchronize(complete: true)
      @reconnect&.call
      recovering = complete && recovery_pending? && !waiting?
      @reconciled = false
      if recovering && @transport.respond_to?(:reconcile)
        @transport.reconcile(@table_id)
        @reconciled = true
      end
      result = yield
      # A successful chat/users refresh does not prove that a previously
      # failed game read or game switch has recovered.
      synchronized! if complete && (recovering || !recovery_pending?)
      result
    rescue StandardError => error
      failed!(error)
      raise
    ensure
      @reconciled = false
    end

    def synchronized!
      @recovery_pending = false
      @recovering = false
      @retry_not_before = 0.0
      @next_reconcile_at = Float::INFINITY
      self
    end

    def failed!(error)
      raise error unless GameRoomNetworkErrors.expected?(error) || GameRoomNetworkErrors.cancelled?(error)
      delay = GameRoomNetworkErrors.retry_delay(error, normal: @error_backoff, rate_limit: @rate_limit_backoff)
      @recovery_pending = true
      @recovering = false
      @retry_not_before = [@retry_not_before.to_f, now + delay].max
      @next_reconcile_at = @retry_not_before
      self
    end

    def request_recovery!(delay: 0)
      @recovery_pending = true
      @retry_not_before = [@retry_not_before.to_f, now + [delay.to_f, 0.0].max].max
      @next_reconcile_at = @retry_not_before
      self
    end

    def recovery_pending?
      @recovery_pending || @recovering
    end

    def waiting?
      recovery_pending? && now < @retry_not_before.to_f
    end

    def reconciled?
      @reconciled == true
    end

    private

    def consume_game_change
      if @transport.respond_to?(:consume_room_game_change)
        @transport.consume_room_game_change(@table_id)
      else
        @transport.consume_game_change(@session_id)
      end
    end

    def now
      @clock.call.to_f
    end

    def positive_identifier(value)
      [value.to_i, 0].max
    end

    def positive_duration(value, name)
      duration = Float(value)
      raise ArgumentError, "#{name} must be finite and greater than zero" if !duration.finite? || duration <= 0

      duration
    rescue TypeError, ArgumentError
      raise ArgumentError, "#{name} must be finite and greater than zero"
    end
  end
end
