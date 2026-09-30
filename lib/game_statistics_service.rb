require "thread"
require "json"
require_relative "game_statistics_periods"
require_relative "game_statistics_queue"
require_relative "game_statistics_store"
require_relative "game_statistics_identity"
require_relative "game_room_analytics_job"
require_relative "network_errors"

module GameRoomStatistics
  class Service
    MAX_SEEN = 1024

    attr_reader :store, :last_error, :work_status

    def initialize(program:, user:, queue: nil, store: nil, clock: nil,
      current_user: -> { Session.name }, trigger: nil, storage: program, enabled: -> { true },
      clock_ready: nil, synchronize_clock: -> { GameRoomClock.synchronize },
      monotonic: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @user = user.is_a?(String) ? user.dup.freeze : user
      @clock, @current_user, @trigger = clock || -> { GameRoomClock.now }, current_user, trigger
      @clock_ready = clock_ready || (clock ? -> { true } : -> { GameRoomClock.synchronized? })
      @synchronize_clock, @monotonic = synchronize_clock, monotonic
      @enabled, @closed = enabled, false
      @seen, @staged, @enqueue_mutex, @flush_mutex = {}, {}, Mutex.new, Mutex.new
      @pending_visits = []
      @queue = queue || Queue.new(storage: storage, user: @user, before_write: -> { check_context!(@flush_token) })
      @store = store || Store.new(app_uuid: program.respond_to?(:server_app_uuid) ? program.server_app_uuid : program.class.server_app_uuid,
        user: @user, current_user: current_user)
    rescue StandardError => error
      failed(error)
    end

    def visit
      return enqueue({"kind" => "visit", "day_key" => day_key(@clock.call)}) if @clock_ready.call
      check_context!
      @enqueue_mutex.synchronize do
        check_context!
        raise QueueFull, "Statistics visit queue is full" if @pending_visits.length >= Queue::MAX_PENDING
        @pending_visits << @monotonic.call
      end
      @trigger&.call
      true
    rescue StandardError => error
      failed(error)
    end

    def started(session:, game_id:)
      metadata = session.is_a?(Hash) && session["__statistics"]
      return false unless valid_game?(game_id) && Identity.valid?(metadata, require_started_at: true)
      enqueue(match_payload("started", metadata, game_id, metadata["started_at"]))
    rescue StandardError => error
      failed(error)
    end

    def observe(session:, replay:, game_id:, viewer:, participants:)
      return false unless session.is_a?(Hash) && valid_game?(game_id)
      added = started(session: session, game_id: game_id)
      metadata = session["__statistics"]
      finished = replay && replay.finished?
      epoch = completion_epoch(replay) if finished && !session["__aborted"]
      if replay && !session["__aborted"] && human_viewer?(session, viewer, participants)
        today = day_key(@clock.call)
        if !finished || (epoch && day_key(epoch) == today)
          mode = if Identity.valid?(metadata, require_started_at: true)
            metadata["mode"]
          else
            legacy_mode(session, participants)
          end
          added = enqueue({"kind" => "player", "game" => game_id, "day_key" => today,
            "mode" => mode}) || added
        end
      end
      if Identity.valid?(metadata, require_started_at: true) && epoch
        added = enqueue(match_payload("completed", metadata, game_id, epoch)) || added
      end
      added
    rescue StandardError => error
      failed(error)
    end

    def flush(token = nil, upload: true)
      @flush_mutex.synchronize do
        @flush_token = token
        begin
          flush_pending(token, upload: upload)
        ensure
          @flush_token = nil
        end
      end
    rescue StandardError => error
      failed(error)
    end

    def close
      @closed = true
    end

    private

    def flush_pending(token, upload:)
      check_context!(token)
      # UI/runner callbacks stage only immutable values. All disk and server
      # access happens here on the existing managed extension worker.
      full = false
      begin
        persist_staged(token)
        if resolve_visits(token, upload: upload)
          persist_staged(token)
        end
      rescue QueueFull
        # Drain the durable backlog before retrying the still-staged entries.
        # Otherwise a full disk queue would prevent its own upload forever.
        full = true
      end
      entries = @queue.batch(limit: 50)
      check_context!(token)
      unless upload
        payloads_pending = @enqueue_mutex.synchronize { !@staged.empty? }
        @work_status = payloads_pending && !full ? :persist_more : (entries.empty? && !staged? ? :idle : :waiting)
        return true
      end
      if entries.empty?
        @work_status = staged? ? :more : :idle
        @last_error = nil
        return true
      end
      confirmed = @store.write_batch(entries.map(&:last), cancellation_token: token)
      unless confirmed.instance_of?(Integer) && confirmed.between?(1, entries.length)
        raise Unavailable, "Statistics upload was not confirmed"
      end
      check_context!(token)
      remaining = nil
      @queue.acknowledge(entries.first(confirmed)) { |pending| remaining = pending }
      # A persisted backlog must drain without relying on a periodic poll.
      @work_status = staged? || remaining.positive? ? :more : :idle
      @last_error = nil
      true
    rescue StandardError => error
      failed(error)
    end

    def persist_staged(token = nil)
      check_context!(token)
      staged = @enqueue_mutex.synchronize { @staged.first(50) }
      return if staged.empty?
      @queue.push_many(staged)
      @enqueue_mutex.synchronize do
        staged.each { |key, payload| @staged.delete(key) if @staged[key].equal?(payload) }
      end
    rescue ConflictingPayload => error
      # Reject the conflict, not the unrelated work behind it. The original
      # durable entry remains authoritative and is never overwritten.
      @enqueue_mutex.synchronize { @staged.delete(error.key) } if error.key
      raise
    end

    # Cold UI entry records only monotonic instants. Resolve them in the worker
    # after synchronization; a delayed response across midnight keeps the day
    # of the visit, not the day of upload. Never perform HTTP during backoff.
    def resolve_visits(token, upload:)
      visits = @enqueue_mutex.synchronize { @pending_visits.first(50) }
      return false if visits.empty? || (!upload && !@clock_ready.call)
      check_context!(token)
      @synchronize_clock.call unless @clock_ready.call
      check_context!(token)
      raise GameRoomNetworkErrors::ClockUnavailable, "Statistics clock is not synchronized" unless @clock_ready.call
      epoch, elapsed = @clock.call, @monotonic.call
      visits.each do |instant|
        check_context!(token)
        enqueue({"kind" => "visit", "day_key" => day_key(epoch - (elapsed - instant))}, notify: false)
        @enqueue_mutex.synchronize { @pending_visits.shift }
      end
      true
    end

    def check_context!(token = nil)
      raise GameRoomAnalyticsJob::Cancelled, "Statistics disabled or closed" if @closed || !@enabled.call
      token.raise_if_cancelled! if token
      unless @user.is_a?(String) && !@user.strip.empty? && GameRoomParticipants.same?(@current_user.call, @user)
        raise Unavailable, "Statistics account changed"
      end
    end

    def failed(error)
      if error.is_a?(GameRoomAnalyticsJob::Cancelled)
        @work_status = :waiting
        return false
      end
      @last_error = error
      @work_status = if error.is_a?(ConflictingPayload)
        :more
      elsif error.is_a?(InvalidQueueState) || error.is_a?(InvalidQueueData) || error.is_a?(JSON::ParserError) || error.is_a?(UnsafeReport)
        :blocked
      elsif error.is_a?(IOError) || error.is_a?(SystemCallError) || error.is_a?(Unavailable) || GameRoomNetworkErrors.transient?(error)
        :retry
      else
        :blocked
      end
      begin
        Log.warning("Game Room statistics operation failed") if defined?(Log)
      rescue StandardError
        nil
      end
      false
    end

    def staged?
      @enqueue_mutex.synchronize { !@staged.empty? || !@pending_visits.empty? }
    end

    def completion_epoch(replay)
      replay.accepted_events.to_a.reverse_each do |event|
        epoch = event.is_a?(Hash) && event["created_at"]
        return epoch if epoch.is_a?(Integer) && epoch.positive?
      end
      nil
    end

    def bot?(session, participant)
      GameRoomParticipants.bot?(participant) || session.fetch("__controllers", {}).any? do |name, controller|
        GameRoomParticipants.same?(name, participant) && controller == "bot"
      end
    end

    def legacy_mode(session, participants)
      players = GameRoomParticipants.unique(participants)
      return "bots" if players.any? { |player| bot?(session, player) }
      players.length == 1 ? "solo" : "humans"
    end

    def human_viewer?(session, viewer, participants)
      GameRoomParticipants.same?(viewer, @user) && GameRoomParticipants.includes?(participants, viewer) &&
        !bot?(session, viewer)
    end

    def valid_game?(game_id)
      game_id.is_a?(String) && /\A[a-z][a-z0-9_]{0,31}\z/.match?(game_id)
    end

    def match_payload(kind, metadata, game_id, epoch)
      {"kind" => kind, "game" => game_id, "day_key" => day_key(epoch),
        "mode" => metadata["mode"], "match" => metadata["id"]}
    end

    def day_key(epoch)
      date = Periods.today(clock: -> { Time.at(epoch) })
      raise ArgumentError, "Statistics date is outside the supported range" unless date.year.between?(1970, 9999)
      date.strftime("%Y%m%d").to_i
    end

    def enqueue(payload, notify: true)
      check_context!
      key = if payload["match"]
        [payload["kind"], payload["match"]].join(":")
      else
        [payload["kind"], payload["day_key"], payload["game"], payload["mode"]].compact.join(":")
      end
      added = @enqueue_mutex.synchronize do
        check_context!
        previous = @staged[key] || @seen[key]
        if previous
          raise ConflictingPayload, "Statistics queue key has a different payload" unless Queue.equivalent?(previous, payload)
          return false
        end
        raise QueueFull, "Statistics staging queue is full" if @staged.size >= Queue::MAX_PENDING
        payload = payload.to_h { |field, value| [field.dup.freeze, value.is_a?(String) ? value.dup.freeze : value] }.freeze
        @staged[key] = payload
        @seen[key] = payload
        @seen.shift while @seen.size > MAX_SEEN
        true
      end
      @trigger.call if added && notify && @trigger
      added
    end
  end
end
