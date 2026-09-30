require 'thread'
require_relative 'game_room_preferences'

# One application-owned writer, shared by the widget and every game form.
# Only the five volume keys are optimistic; privacy and other settings still
# enter the cache only after a successful, atomic host update_json.
class GameRoomVolumeSettings
  QUIET_PERIOD = 0.15

  def initialize(values:, runtime: nil, publish:, write:)
    @runtime, @publish, @write = runtime, publish, write
    @lock, @io, @wake = Mutex.new, Mutex.new, ConditionVariable.new
    @pending, @serial = {}, 0
    @base = values
    @snapshot = values
  end

  def snapshot; @lock.synchronize { @snapshot }; end
  def closed?; @lock.synchronize { @closed == true }; end

  def remember(values)
    @lock.synchronize { @base = values; rebuild_snapshot }
  end

  def set(group, value)
    raise ArgumentError, 'Unknown sound group' unless GameRoomPreferences::SOUND_GROUPS.include?(group)
    raise ArgumentError, 'Invalid sound volume' unless value.is_a?(Integer) && value.between?(0, 100)
    @lock.synchronize do
      return false if @closed
      @serial += 1
      @pending[group] = [@serial, value]
      @due = monotonic_time + QUIET_PERIOD
      rebuild_snapshot
      start_worker unless @running
      @wake.signal
    end
    true
  end

  # Explicit Settings saves share the write boundary. Pending earlier hotkeys
  # are merged first; an explicit Save may replace them. Hotkeys pressed while
  # a slow save runs retain their newer serial and are written afterwards.
  def update
    @io.synchronize do
      serial, patch = @lock.synchronize { [@serial, @pending.transform_values(&:last)] }
      result = @write.call(patch) { |state| yield state }
      @lock.synchronize do
        @pending.delete_if { |_group, item| item.first <= serial }
        @base = result
        rebuild_snapshot
      end
      @publish.call(result)
      result
    end
  end

  def take_error
    @lock.synchronize { error, @error = @error, nil; error }
  end

  def close
    thread = @lock.synchronize do
      return if @closed
      @closed = true
      start_worker if !@pending.empty? && !@running
      @wake.broadcast
      @thread
    end
    return unless thread&.alive? && !thread.equal?(Thread.current)

    # Unload waits for the finite final write before a new runtime can write
    # the same file. Tasks keeps the native UI alive; ordinary F2/F3 never waits.
    if defined?(EltenAPI::Tasks) && EltenAPI::Tasks.respond_to?(:run) &&
        defined?($currentthread) && Thread.current.equal?($currentthread)
      EltenAPI::Tasks.run(ui: :none, cancellable: false) { thread.join }
    else
      thread.join
    end
  end

  private

  def monotonic_time; Process.clock_gettime(Process::CLOCK_MONOTONIC); end

  def rebuild_snapshot
    levels = GameRoomPreferences.sound_volumes(@base)
    @pending.each { |group, item| levels[group] = item.last }
    @snapshot = @base.merge('sound_volumes' => levels.freeze).freeze
  end

  def start_worker
    @running = true
    @thread = Thread.new do
      Thread.current.report_on_exception = false
      if @runtime && defined?(Programs) && Programs.respond_to?(:with_runtime)
        Programs.with_runtime(@runtime) { drain }
      else
        drain
      end
    rescue StandardError => error
      failed(error)
    end
  rescue StandardError
    @running = false
    raise
  end

  def drain
    loop do
      ready = @lock.synchronize do
        while !@closed && !@pending.empty? && (delay = @due - monotonic_time) > 0
          @wake.wait(@lock, delay)
        end
        @running = false if @pending.empty?
        !@pending.empty?
      end
      break unless ready
      update { |_state| }
    end
  end

  def failed(error)
    @lock.synchronize { @error = error; @running = false }
    Log.warning("ELTEN Game Room volume save failed: #{error.class}: #{error.message}") if defined?(Log)
  end
end
