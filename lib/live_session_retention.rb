# These helpers run under the store mutex. A disconnected connection is not
# itself a reason to drop data: live membership, pending writes and in-flight
# reads keep their state. Inactive rooms are a small rejoin cache, not an archive.
class GameRoomLiveSessionStore
  module Retention
    INACTIVE_LIMIT = 8
    DISCOVERY_CACHE_LIMIT = 100
    ROOM_MAPS = %i[records record_keys message_records recovered_moves stack_cursors
      received_sequences private_game_messages record_generations validated_records
      published_discovery discovery_retry_at discovery_due activity_publish_at realtime_activity
      attachments control_locks discovered].freeze

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
        @retained_subscriptions[table_id.to_i] = @retained_subscriptions.fetch(table_id.to_i, 0) + 1
      end
    end

    def release_room_subscription(table_id)
      @mutex.synchronize do
        id = table_id.to_i
        count = @retained_subscriptions.fetch(id, 0)
        count > 1 ? @retained_subscriptions[id] = count - 1 : @retained_subscriptions.delete(id)
        prune_inactive_rooms
      end
    end

    private

    def retained_room_ids
      ids = @sessions.keys + @inactive_rooms.keys + @pending_moves.keys + @room_io.keys + @retained_subscriptions.keys
      @recovered_moves.each { |id, moves| ids << id unless moves.empty? }
      @private_game_messages.each { |id, messages| ids << id unless messages.empty? }
      @control_locks.each { |id, lock| ids << id if lock.locked? }
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
        next if @sessions.key?(id) || @pending_moves.key?(id) || @room_io[id].to_i.positive?
        next if @retained_subscriptions.key?(id)
        next unless @recovered_moves.fetch(id, []).empty?
        next unless @private_game_messages.fetch(id, []).empty?
        next if @control_locks[id]&.locked?
        ROOM_MAPS.each { |name| instance_variable_get("@#{name}").delete(id) }
        @clock_revisions.delete_if { |key, _| key.is_a?(Array) && key.first == id }
        @native_session_ids.delete_if { |_, value| value == id }
        @inactive_rooms.delete(id)
      end
    end

    def begin_room_io(table_id)
      @mutex.synchronize { @room_io[table_id] = @room_io.fetch(table_id, 0) + 1 }
    end

    def end_room_io(table_id)
      @mutex.synchronize do
        @room_io[table_id] -= 1
        @room_io.delete(table_id) if @room_io[table_id].zero?
        prune_inactive_rooms
      end
    end
  end
end
