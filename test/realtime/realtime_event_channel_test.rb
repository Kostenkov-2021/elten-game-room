require_relative "../support/realtime_event_channel"

now = 0.0
work, events, program = ChannelWork.new, ChannelWork.new, ChannelProgram.new('Alice')
members = %w[Alice Bob Watcher]
channel = GameRoomRealtime::EventChannel.new(program: program, match: 'match', owner: 'Alice', viewer: 'Alice',
  clock: -> { now }, members: -> { members }, work: work, event_work: events)
channel.enable_events
channel.tick; work.finish; channel.tick; work.finish; channel.tick
session = channel.instance_variable_get(:@session)
session.participants << ChannelParticipant.new(1, 'Bob') << ChannelParticipant.new(2, 'Watcher')
assert(program.endpoints.first.creates.first[:metadata]['events'] == 'pong-local-1', 'missing protocol dialect')
packet = ->(n, epoch = channel.epoch, kind = 'event') {
  GameRoomRealtime::Protocol.encode(match: 'match', epoch: epoch, sequence: n, kind: kind, body: {'action' => 'hit'})
}
session.deliver_event('Mallory', packet.call(1))
session.deliver_event('Bob', packet.call(1, 'old'))
session.deliver_event('Bob', packet.call(1, channel.epoch, 'input'))
assert(channel.take_events.empty?, 'unauthorized event delivered')
[1, 2, 2, 1, 3].each { |n| session.deliver_event('Bob', packet.call(n)) }
assert(channel.take_events.map { |_, p| p['n'] } == [1, 2, 3], 'reliable lane lost ordering/dedup')
data = packet.call(4)
assert(channel.send_event(data) && events.operation && session.reliable_sent == nil, 'send must start background work immediately, not perform RPC in UI caller')
channel.tick
assert(events.operation && session.reliable_sent == nil, 'send did not enter finite worker')
events.finish; channel.tick
assert(session.reliable_sent == [[data, %w[Bob Watcher]]], 'reliable routing')
assert(!channel.send_event('x' * 1201), 'oversize reliable packet')

# A failing old send cannot close an already replaced endpoint.
channel.send_event(packet.call(5)); channel.tick
session.reliable_error = true
channel.reconnect
events.finish; channel.tick
assert(channel.last_exception.nil?, 'stale failure contaminated replacement')
work.finish if work.operation
channel.tick
channel.close
assert(program.endpoints.all?(&:closed?), 'event endpoint leaked')

# Bounded queues: unconsumed native traffic schedules a reconnect, not growth.
work, events, program = ChannelWork.new, ChannelWork.new, ChannelProgram.new('Alice')
channel = GameRoomRealtime::EventChannel.new(program: program, match: 'match', owner: 'Alice', viewer: 'Alice',
  clock: -> { now }, members: -> { members }, work: work, event_work: events)
channel.enable_events
channel.tick; work.finish; channel.tick; work.finish; channel.tick
session = channel.instance_variable_get(:@session)
129.times { |i| session.deliver_event('Bob', packet.call(i + 10)) }
assert(channel.take_events.empty? && channel.instance_variable_get(:@reconnect_requested), 'inbox overflow not reset')
channel.close
puts 'PASS reliable event channel: bounded async send, authenticated ordered receive, dialect, stale failure, cleanup'
