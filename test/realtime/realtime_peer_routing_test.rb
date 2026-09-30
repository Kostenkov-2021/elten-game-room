require_relative "../support/realtime_event_channel"

now = 0.0
work, sends = ChannelWork.new, ChannelWork.new
names = %w[Alice Bob Carol Dave Watcher]
channel = GameRoomRealtime::EventChannel.new(program: ChannelProgram.new('Bob'), match: 'peers', owner: 'Alice', viewer: 'Bob',
  clock: -> { now }, members: -> { names }, work: work, event_work: sends)
channel.enable_events('pong-doubles-peer-2', routing: :peers)
channel.required_members = %w[Alice Carol Dave]
channel.tick; work.finish; channel.tick
endpoint = channel.instance_variable_get(:@endpoint)
session = ChannelSession.new('peer-session', 'Bob', names)
base = {'gr_realtime' => 1, 'match' => 'peers'}
old = ChannelInvitation.new(session, metadata: base.merge('events' => 'pong-doubles-1'))
endpoint.deliver(old); channel.tick
assert(old.accepts.zero?, 'new protocol silently joined an incompatible owner-mediated match')
invitation = ChannelInvitation.new(session, metadata: base.merge('events' => 'pong-doubles-peer-2'))
endpoint.deliver(invitation); channel.tick; work.finish; channel.tick
packet = ->(n) { GameRoomRealtime::Protocol.encode(match: 'peers', epoch: channel.epoch,
  sequence: n, kind: 'event', body: {'action' => 'hit'}) }
session.deliver_event('Mallory', packet.call(1))
session.deliver_event('Carol', packet.call(1))
session.deliver_event('Carol', packet.call(1))
session.deliver_event('Dave', packet.call(1))
assert(channel.take_events.map(&:first) == %w[carol dave], 'peer routing lost authorization or per-sender deduplication')
data = packet.call(2)
channel.send_event(data); channel.tick; sends.finish; channel.tick
assert(session.reliable_sent == [[data, %w[Alice Carol Dave Watcher]]], 'peer actions were relayed through the owner instead of direct recipients')
channel.close
puts 'PASS direct peer routing: dialect isolation, native sender roster, independent sequence streams, one relay fanout'
