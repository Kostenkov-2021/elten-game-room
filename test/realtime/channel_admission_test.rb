require_relative '../support/native_background_capacity'
require_relative '../support/realtime_event_channel'
include GameRoomTest::Assertions

# The Communications endpoint/session objects are existing deterministic SDK
# fixtures. Work/Tasks/FIFO are actual native implementations, not fake starts.
failures = []
[0, 128].each do |backlog|
  %i[endpoint accept invite depart reliable].each do |phase|
    GameRoomTest::NativeBackgroundCapacity.with(backlog) do |work, free_capacity|
      now = 0.0
      previous = nil
      viewer = %i[accept depart].include?(phase) ? 'Bob' : 'Alice'
      members = [viewer]
      program = ChannelProgram.new(viewer)
      bootstrap = ChannelWork.new
      channel_class = phase == :reliable ? GameRoomRealtime::EventChannel : GameRoomRealtime::Channel
      arguments = {program: program, match: 'match', owner: 'Alice', viewer: viewer,
        clock: -> { now }, members: -> { members }, work: bootstrap}
      arguments[:event_work] = work if phase == :reliable
      channel = channel_class.new(**arguments)
      channel.enable_events if phase == :reliable
      unless phase == :endpoint
        # Normal state transitions establish the fixture endpoint/session;
        # they are not part of the native admission test under examination.
        channel.tick; bootstrap.finish; channel.tick
        if viewer == 'Alice'
          bootstrap.finish; channel.tick
        end
      end
      if phase != :reliable
        bootstrap.close
        channel.instance_variable_set(:@work, GameRoomRealtime::Operation.new(clock: -> { now }, work: work))
      end
      members = %w[Alice Bob] unless phase == :endpoint
      endpoint = program.endpoints.first
      case phase
      when :endpoint
        channel.tick
        assert(program.endpoints.empty?, 'Endpoint opened before native capacity was available')
      when :accept
        accepted = ChannelSession.new('accepted', viewer, members)
        invitation = ChannelInvitation.new(accepted)
        endpoint.enqueue(invitation)
        channel.tick
        assert_equal(0, invitation.accepts)
        if backlog == 128
          assert(channel.instance_variable_get(:@pending_invitation).equal?(invitation),
            'Refused admission consumed the only pending invitation')
        end
      when :invite
        session = channel.instance_variable_get(:@session)
        channel.tick
        assert(session.invites.empty?, 'Invitation sent before native capacity was available')
        assert(channel.instance_variable_get(:@invite_attempts).empty?,
          'Unadmitted invitation was counted as an attempt') if backlog == 128
      when :depart
        current = ChannelSession.new('current', viewer, members)
        previous = ChannelSession.new('previous', viewer, members)
        channel.__send__(:attach, current)
        channel.instance_variable_set(:@departing, previous)
        channel.tick
        assert_equal(:open, previous.state)
        if backlog == 128
          assert(channel.instance_variable_get(:@departing).equal?(previous),
            'Refused admission discarded the previous session departure')
        end
      when :reliable
        session = channel.instance_variable_get(:@session)
        session.participants << ChannelParticipant.new(1, 'Bob')
        data = GameRoomRealtime::Protocol.encode(match: 'match', epoch: channel.epoch,
          sequence: 1, kind: 'event', body: {'action' => 'hit'})
        assert(channel.send_event(data), 'A queued reliable event was rejected')
        assert(session.reliable_sent.nil?, 'Reliable write ran before native capacity was available')
        assert_equal(backlog == 128 ? 1 : 0, channel.instance_variable_get(:@event_outbox).size)
      end
      assert(channel.internal_error.nil?, 'Local capacity was latched as a broken connection')
      free_capacity.call
      now = 2.0
      GameRoomTest::NativeBackgroundCapacity.until_true do
        channel.tick
        case phase
        when :endpoint then channel.connected?
        when :accept then channel.connected? && invitation.accepts == 1
        when :invite then session.invites == ['Bob'] && !work.busy?
        when :depart then previous.state == :closed && !work.busy?
        when :reliable then session.reliable_sent.to_a.size == 1 && !work.busy?
        end
      end
      assert(channel.internal_error.nil?, 'Recovered capacity left a permanent internal error')
      assert_equal(1, invitation.accepts) if phase == :accept
      assert_equal(['Bob'], session.invites) if phase == :invite
    rescue StandardError => error
      failures << {phase: phase, backlog: backlog, error: error.class.name, message: error.message,
        backtrace: error.backtrace.first(3)}
    ensure
      channel&.close
      previous&.close
    end
  end
end
assert(failures.empty?, "Realtime admission failures: #{failures.inspect}")
puts 'PASS real native admission: endpoint/accept/invite/depart/reliable intents survive4+128 capacity without connection failure, lost accept or lost leave'
