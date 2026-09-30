module GameRoomPong
  class Client
    # These are client-owned lifetimes. Reset policies stay with each game's
    # client; no shared physics or implicit reset is introduced here.
    ConnectionState = Struct.new(:peers, :sequence, :event_sequence, :next_send, :last_reconnect, :connection_started_at, :epoch, keyword_init: true)
    RallyState = Struct.new(:engine, :snapshot, :paused, :physics_at, :physics_updated_at, :rotation, :deferred_events, :ready_at, :serve_announce_at, keyword_init: true)
    PointState = Struct.new(:pending_point, :point_reason, :goal_preview, keyword_init: true)
    PresentationState = Struct.new(:announced_rally, keyword_init: true)

    def engine; rally_state.engine; end
    def snapshot; rally_state.snapshot; end
    def paused; rally_state.paused; end

    private

    def connection_state
      @connection_state ||= ConnectionState.new
    end

    def rally_state
      @rally_state ||= RallyState.new
    end

    def point_state
      @point_state ||= PointState.new
    end

    def presentation_state
      @presentation_state ||= PresentationState.new
    end

  end
end
