require_relative "../support/realtime_channel"

class StrictChannelInvitation < ChannelInvitation
  attr_reader :id, :calls
  attr_accessor :before_accept, :fail_accept
  def initialize(session, id: 'one-invitation', **options)
    super(session, **options)
    @id, @calls = id, 0
  end
  def accept
    @calls += 1
    raise EltenAPI::Communication::SessionClosed, 'invitation no longer pending' unless status == :pending
    @before_accept&.call
    raise EltenAPI::Communication::ConnectionError, 'temporary accept failure' if @fail_accept
    super
  end
end

def invitation_rig
  time = [0.0]
  workers = []
  factory = -> { ChannelWork.new.tap { |work| workers << work } }
  program = ChannelProgram.new('Bob')
  guest = GameRoomRealtime::Channel.new(program: program, match: 'match', owner: 'Alice', viewer: 'Bob',
    clock: -> { time[0] }, members: -> { %w[Alice Bob] }, work_factory: factory)
  guest.tick; workers.last.finish; guest.tick
  [guest, program.endpoints.last, workers, time]
end

# Native ELTEN offers the SAME pending object through both its callback and
# next_invitation. The queue copy can be observed before async accept completes.
guest, endpoint, workers, = invitation_rig
session = ChannelSession.new('race-session', 'Bob', %w[Alice Bob])
invitation = StrictChannelInvitation.new(session)
endpoint.deliver(invitation)
guest.tick
endpoint.enqueue(invitation)
guest.tick
workers.last.finish
guest.tick
workers.last.finish if workers.last.operation
guest.tick
assert(invitation.calls == 1, 'callback and queue accepted the same invitation twice')
assert(guest.connected? && guest.last_error.nil?, 'duplicate poisoned a successfully attached session')
assert(guest.instance_variable_get(:@session).equal?(session), 'working session was replaced')
guest.close

# Another wrapper of the same native invitation ID must not bypass the guard.
guest, endpoint, workers, = invitation_rig
session = ChannelSession.new('id-race', 'Bob', %w[Alice Bob])
first = StrictChannelInvitation.new(session)
copy = StrictChannelInvitation.new(session)
endpoint.deliver(first); guest.tick
endpoint.enqueue(copy); guest.tick
workers.last.finish; guest.tick
endpoint.deliver(copy); guest.tick
assert(first.calls == 1 && copy.calls.zero?, 'duplicate ID started a second acceptance')
assert(guest.connected? && guest.last_error.nil?, 'ID dedup lost the good session')
guest.close

# Cancellation can happen before the worker starts, or during native accept.
[:close, :reconnect, :cancelled].each do |reason|
  guest, endpoint, workers, = invitation_rig
  invitation = StrictChannelInvitation.new(ChannelSession.new(reason.to_s, 'Bob', %w[Alice Bob]))
  endpoint.deliver(invitation); guest.tick
  pending = workers.last
  case reason
  when :close then guest.close
  when :reconnect then guest.reconnect; guest.tick
  when :cancelled then invitation.instance_variable_set(:@status, :cancelled)
  end
  pending.finish
  guest.tick
  assert(invitation.calls.zero?, "#{reason} started a stale acceptance RPC")
  assert(!guest.connected?, "#{reason} attached a stale session")
  guest.close
end
guest, endpoint, workers, = invitation_rig
session = ChannelSession.new('late-accept', 'Bob', %w[Alice Bob])
invitation = StrictChannelInvitation.new(session)
invitation.before_accept = -> { guest.close }
endpoint.deliver(invitation); guest.tick; workers.last.finish
assert(session.state == :closed && !guest.connected?, 'late acceptance leaked its native session')

# A failed attempt must not make the next valid invitation unacceptably "seen".
guest, endpoint, workers, = invitation_rig
bad = StrictChannelInvitation.new(ChannelSession.new('bad', 'Bob', %w[Alice Bob]), id: 'bad')
bad.fail_accept = true
endpoint.deliver(bad); guest.tick; workers.last.finish; guest.tick
good = StrictChannelInvitation.new(ChannelSession.new('good', 'Bob', %w[Alice Bob]), id: 'good')
endpoint.enqueue(good); guest.tick; workers.last.finish; guest.tick
assert(bad.calls == 1 && good.calls == 1 && guest.connected? && guest.last_error.nil?, 'accept failure prevented recovery')
guest.close

puts 'PASS invitation race: callback/queue/ID dedup, close/reconnect/cancel races, late cleanup and retry'
