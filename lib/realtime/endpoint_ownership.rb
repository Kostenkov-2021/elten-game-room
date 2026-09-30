require 'thread'

module GameRoomRealtime
  # Program#communication returns a cached endpoint, not an owned new object.
  # Serialize only setup workers across channel generations. UI cancellation
  # never waits for this lock. The short ownership lock protects an endpoint
  # handed to a successor from cleanup belonging to an earlier channel.
  class EndpointOwnership
    REGISTRY_LOCK = Mutex.new

    def self.for(program)
      REGISTRY_LOCK.synchronize do
        program.instance_variable_get(:@game_room_endpoint_ownership) ||
          program.instance_variable_set(:@game_room_endpoint_ownership, new(program))
      end
    end

    def initialize(program)
      @program = program
      @opening, @ownership = Mutex.new, Mutex.new
      @owners = {}.compare_by_identity
    end

    def open(current:, owner:)
      @opening.synchronize do
        return unless current.call
        endpoint = @program.communication
        if yield(endpoint)
          endpoint
        else
          release(endpoint, owner: owner)
          nil
        end
      end
    end

    def claim(endpoint, owner:)
      @ownership.synchronize { @owners[endpoint] = owner }
    end

    def release(endpoint, owner:)
      return unless endpoint
      @ownership.synchronize do
        return if @owners.key?(endpoint) && !@owners[endpoint].equal?(owner)
        begin
          endpoint.close unless endpoint.closed?
        ensure
          @program.release(endpoint) if @program.respond_to?(:release)
          @owners.delete(endpoint)
        end
      end
    end
  end
end
