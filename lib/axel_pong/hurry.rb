require_relative "../game_room_localization"

module GameRoomPong
  using GameRoomLocalization::Translations
  # Only the channel owner measures the ten seconds. Never compare clocks
  # from different machines or let an observer invent a penalty.
  module Hurry
    def request_hurry
      return false unless @side != nil && @engine && !@paused &&
        @engine.goal == nil && @engine.turn.zero? && @rotation.team(@side) != @rotation.team(@engine.server)
      data = {'action' => 'hurry_request', 'side' => @side, 'turn' => 0}
      host? ? accept_hurry(data) : emit_peer_event(data)
      true
    end

    private

    def accept_hurry(data)
      side = data['side']
      now = @clock.call
      return false if @paused || now < @ready_at || @engine.goal || !@engine.turn.zero? ||
        @rotation.team(side) == @rotation.team(@engine.server)
      return false if @hurry_until || now < (@hurry_cooldowns || {}).fetch(side, 0.0)
      @hurry_cooldowns ||= {}
      @hurry_cooldowns[side] = now + 15.0
      @hurry_until = now + 10.0
      warning = {'action' => 'hurry', 'side' => @engine.server, 'turn' => 0}
      announce_hurry(warning)
      emit_peer_event(warning)
      true
    end

    def announce_hurry(data)
      turn = @side == nil && !host? ? @observer_turn.to_i : @engine.turn
      goal = @side == nil && !host? ? @snapshot && @snapshot['goal'] : @engine.goal
      return false unless turn.zero? && !goal && data['side'] == @engine.server
      speak(_('%{player}, serve within ten seconds or your opponent receives a point.') % {
        player: GameRoomContent.utf8(GameRoomParticipants.display_name(@players[data['side']])) })
      true
    end

    def hurry_tick(healthy)
      return unless host? && @hurry_until
      unless healthy && @engine.turn.zero? && !@engine.goal
        @hurry_until = nil
        return
      end
      return if @clock.call < @hurry_until
      @hurry_until = nil
      return unless @engine.serve_timeout
      @point_reason = 'timeout'
      emit_peer_event('action' => 'timeout', 'side' => @engine.server, 'turn' => @engine.turn)
    end
  end
end
