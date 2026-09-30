require "thread"

# Finite native tasks, drained by their owners' existing updates. ELTEN limits
# a runtime to four workers; pending work waits in FIFO order without another
# scheduler, UI pump, thread or retrying the operation itself.
module GameRoomBackground
  module Pending
    LIMIT = 128
    LOCK = Mutex.new
    @items = []

    def self.add(work)
      LOCK.synchronize do
        raise EltenAPI::Tasks::Busy, "Game Room background queue is full" if @items.length >= LIMIT
        @items << work
      end
      dispatch
    end

    def self.remove(work)
      LOCK.synchronize { @items.delete(work) }
    end

    def self.dispatch
      return unless LOCK.try_lock
      begin
        blocked = {}
        @items.delete_if do |work|
          next false if blocked[work.scope]
          started = work.dispatch
          blocked[work.scope] = true unless started
          started
        end
      ensure
        LOCK.unlock
      end
    end
  end
  private_constant :Pending

  class Work
    def initialize(runtime: nil)
      @runtime = runtime || (Programs.current_runtime if defined?(Programs) && Programs.respond_to?(:current_runtime))
      if @runtime == nil && defined?(Programs)
        @runtime = Programs.runtime_for(self) if Programs.respond_to?(:runtime_for)
        @runtime ||= Programs.runtime_from_caller if Programs.respond_to?(:runtime_from_caller)
      end
      @lock = Mutex.new
      @managed_resources = EltenAPI::Resources::Registry.new
      @closed = false
      @runtime&.manage(self)
    end

    attr_reader :managed_resources

    def scope; @runtime&.manifest&.id&.downcase; end
    def closed?; @lock.synchronize { @closed }; end

    def busy?
      Pending.dispatch
      @lock.synchronize { !@closed && !!(@operation || @handle || @result) }
    end

    def start(&operation)
      raise ArgumentError, "operation is required" unless operation
      @lock.synchronize do
        return false if @closed || @operation || @handle || @result
        @operation = operation
      end
      Pending.add(self)
      true
    rescue EltenAPI::Tasks::Busy
      @lock.synchronize { @operation = nil }
      raise
    end

    def take
      Pending.dispatch
      @lock.synchronize do
        return nil if @closed
        if @result
          result, @result = @result, nil
          return result
        end
        outcome = @handle&.take
        if outcome
          @handle = nil
          return [outcome.value, outcome.error]
        end
        # Native runtime/owner teardown may discard an unfinished result.
        @handle = nil if @handle&.state == :closed
        nil
      end
    end

    def close
      @lock.synchronize do
        return if @closed
        @closed = true
        @operation = @result = nil
        @handle&.close # Discard only: never cancel/kill an uncertain write.
        @handle = nil
        @managed_resources.close
      end
      Pending.remove(self)
      @runtime&.release(self)
      nil
    end

    # Called only by the shared queue. Busy is capacity, not a failed action;
    # retain the untouched operation until an existing owner update retries.
    def dispatch
      @lock.synchronize do
        return true if @closed || !@operation
        operation = @operation
        start = -> { EltenAPI::Tasks.start(owner: self) { operation.call } }
        @handle = if defined?(Programs) && Programs.respond_to?(:with_runtime)
          Programs.with_runtime(@runtime, &start)
        else
          start.call
        end
        @operation = nil
        true
      rescue EltenAPI::Tasks::Busy
        false
      rescue StandardError => error
        @operation = nil
        @result = [nil, error]
        true
      end
    end
  end
end
