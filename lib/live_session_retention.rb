# These helpers run under the store mutex. A disconnected connection is not
# itself a reason to drop data: live membership, pending writes and in-flight
# reads keep their state. Inactive rooms are a small rejoin cache, not an archive.
class GameRoomLiveSessionStore
  module Retention
    INACTIVE_LIMIT = 8
    DISCOVERY_CACHE_LIMIT = 100
    ROOM_MAPS = %i[published_discovery discovery_retry_at discovery_due activity_publish_at
      realtime_activity discovered].freeze

    # Local only. The fixed lock order is Store -> Transport -> Repository.
    # Keep the snapshot and dependent cleanup in one critical section so a
    # concurrently attached membership cannot be deleted using an older list.
    def with_retained_rooms
      @mutex.synchronize do
        prune_inactive_rooms
        yield retained_room_ids
      end
    end

    def retain_room_subscription(table_id)
      @mutex.synchronize do
        room_state(table_id.to_i).subscription_count += 1
      end
    end

    def release_room_subscription(table_id)
      @mutex.synchronize do
        id = table_id.to_i
        state = @rooms[id]
        state.subscription_count = [state.subscription_count - 1, 0].max if state
        prune_inactive_rooms
      end
    end

    private

    def retained_room_ids
      ids = @sessions.keys + @inactive_rooms.keys
      @rooms.each { |id, state| ids << id if state.retained? }
      ids.to_h { |id| [id, true] }
    end

    def replace_discovered_cache(found)
      @mutex.synchronize do
        retained = retained_room_ids
        protected = @discovered.select { |id, _| retained[id] }
        current = protected.merge(found)
        unprotected = current.reject { |id, _| retained[id] }.to_a.last(DISCOVERY_CACHE_LIMIT).to_h
        @discovered = current.select { |id, _| retained[id] }.merge(unprotected)
      end
    end

    def retain_inactive_room(table_id)
      return if @sessions.key?(table_id)
      @inactive_rooms.delete(table_id)
      @inactive_rooms[table_id] = true
      prune_inactive_rooms
    end

    def prune_inactive_rooms
      @inactive_rooms.keys.each do |id|
        break if @inactive_rooms.length <= INACTIVE_LIMIT
        next if @sessions.key?(id) || @rooms[id]&.retained?
        ROOM_MAPS.each { |name| instance_variable_get("@#{name}").delete(id) }
        @rooms.delete(id)
        @native_session_ids.delete_if { |_, value| value == id }
        @inactive_rooms.delete(id)
      end
    end

    def begin_room_io(table_id)
      @mutex.synchronize { room_state(table_id).io_count += 1 }
    end

    def end_room_io(table_id)
      @mutex.synchronize do
        room_state(table_id).io_count -= 1
        prune_inactive_rooms
      end
    end
  end
end
