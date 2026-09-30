require_relative "../support/realtime_receive_poll"

now = 0.0
work, events, program = ChannelWork.new, ChannelWork.new, ChannelProgram.new('Alice')
members = %w[Alice Bob Watcher]
channel = GameRoomRealtime::EventChannel.new(program: program, match: 'match', owner: 'Alice', viewer: 'Alice',
  clock: -> { now }, members: -> { members }, work: work, event_work: events)
channel.enable_events('poll-test', routing: :peers)
channel.instance_variable_set(:@endpoint, ChannelEndpoint.new('Alice'))
session = QueuedChannelSession.new('native-poll-test', 'Alice', members)
channel.__send__(:attach, session)
packet = ->(n, kind = 'event', epoch = channel.epoch) {
  GameRoomRealtime::Protocol.encode(match: 'match', epoch: epoch, sequence: n, kind: kind, body: {'action' => 'hit'})
}

# A packet arrives while ELTEN is sleeping AFTER this frame's callback pass.
# Game Room may consume the native in-memory queue now, without dispatching UI.
session.arrive(:reliable, 'Bob', packet.call(1))
session.arrive(:unreliable, 'Bob', packet.call(5, 'input'))
now = 0.05
channel.tick
assert(channel.take_events.map { |_, p| p['n'] } == [1], 'received action waited for a later native callback pass')
assert(channel.take_packets['bob']&.[]('n') == 5, 'received position waited for a later native callback pass')
session.dispatch
assert(channel.take_events.empty? && channel.take_packets.empty?, 'late native callback repeated a polled message')

# Callback-first and mixed delivery use exactly the same ordering and guards.
session.arrive(:reliable, 'Bob', packet.call(2))
session.dispatch
session.arrive(:reliable, 'Bob', packet.call(3))
session.arrive(:reliable, 'Mallory', packet.call(4))
session.arrive(:reliable, 'Bob', packet.call(4, 'event', 'old-epoch'))
session.arrive(:unreliable, 'Watcher', packet.call(99, 'input'))
members.delete('Watcher')
channel.tick
assert(channel.take_events.map { |_, p| p['n'] } == [2, 3], 'mixed callback/poll ordering or authentication changed')
assert(channel.take_packets.empty?, 'removed member was accepted from native queue')
session.dispatch
assert(channel.take_events.empty?, 'mixed delivery was applied twice')
channel.close
previous = session.polls
channel.tick
assert(session.polls == previous, 'closed channel polled a retired session')

# A reliable gap found by polling uses the same recovery guard as callbacks.
channel = GameRoomRealtime::EventChannel.new(program: program, match: 'match', owner: 'Alice', viewer: 'Alice',
  clock: -> { now }, members: -> { members }, work: ChannelWork.new, event_work: ChannelWork.new)
channel.enable_events('poll-test', routing: :peers)
channel.instance_variable_set(:@endpoint, ChannelEndpoint.new('Alice'))
session = QueuedChannelSession.new('gap', 'Alice', members)
channel.__send__(:attach, session)
session.arrive(:reliable, 'Bob', packet.call(1))
session.arrive(:reliable, 'Bob', packet.call(3))
session.arrive(:reliable, 'Bob', packet.call(2))
channel.tick
assert(channel.last_error == 'ReliableSequenceGap', 'poll bypassed reliable gap recovery')
assert(channel.take_events.empty?, 'recovery retained events from an invalidated stream')
session.dispatch
assert(channel.take_events.empty?, 'callbacks applied obsolete messages after recovery was requested')
channel.tick
assert(!channel.connected?, 'poll gap did not close the old connection')
channel.close

# A delayed callback from a replaced session cannot enter the new epoch.
channel = GameRoomRealtime::EventChannel.new(program: program, match: 'match', owner: 'Alice', viewer: 'Alice',
  clock: -> { now }, members: -> { members }, work: ChannelWork.new, event_work: ChannelWork.new)
channel.enable_events('poll-test', routing: :peers)
channel.instance_variable_set(:@endpoint, ChannelEndpoint.new('Alice'))
old_session = QueuedChannelSession.new('old', 'Alice', members)
channel.__send__(:attach, old_session)
old_session.arrive(:reliable, 'Bob', packet.call(1))
new_session = QueuedChannelSession.new('new', 'Alice', members)
channel.__send__(:attach, new_session)
old_session.dispatch
assert(channel.take_events.empty?, 'retired session callback entered a replacement')
new_session.arrive(:reliable, 'Bob', packet.call(1))
channel.tick
assert(channel.take_events.length == 1, 'replacement session failed to start its own sequence')
assert(old_session.polls.zero?, 'replacement drained the retired session')
channel.close
puts 'PASS receive poll: nonblocking same-frame dispatch, callback dedup, authentication, ordering and close'
