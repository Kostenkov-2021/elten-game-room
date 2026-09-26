require_relative 'support/post_233_ping'
require_relative 'support/realtime_channel'
require EltenTestHost.file('src/eapi/communication.rb')

# Real host status/freshness logic, without starting sockets or workers.
clock = 10.0
paths = EltenLink::Relay::P2PTransport.allocate
paths.instance_variable_set(:@mutex, Mutex.new)
paths.instance_variable_set(:@failed, false)
paths.define_singleton_method(:enabled?) { true }
paths.define_singleton_method(:monotonic) { clock }
peer = ->(rtt) { EltenLink::Relay::P2PTransport::Peer.new(selected: ['local', 1], last_pong: clock, rtt: rtt) }
bob, watcher = peer.call(0.0236), peer.call(0.0061)
native_state = {active: true, self_id: 0, participants: [0, 1, 2, 3], peers: {1 => bob, 2 => watcher, 3 => peer.call(0.001)}}
paths.instance_variable_set(:@sessions, {'native-session' => native_state})

program, work = ChannelProgram.new('Alice'), ChannelWork.new
members = ['Alice']
channel = GameRoomRealtime::Channel.new(program: program, match: 'ping-p2p', owner: 'Alice', viewer: 'Alice',
  clock: -> { clock }, members: -> { members }, work: work)
channel.tick; work.finish; channel.tick; work.finish; channel.tick
members.concat(%w[Bob Watcher])
endpoint = program.endpoints.first
session = channel.instance_variable_get(:@session)
session.participants.concat([ChannelParticipant.new(1, 'Bob'), ChannelParticipant.new(2, 'Watcher'), ChannelParticipant.new(3, 'Unrelated')])
session.define_singleton_method(:p2p) { :full }
session.define_singleton_method(:p2p_status) { paths.status(id) }
udp = true
endpoint.define_singleton_method(:fast_path?) { udp }
endpoint.define_singleton_method(:latency) { raise 'Stale UDP RTT read' unless udp; 0.015 }
ping = GameRoomPing.new(program, worker: PingManualWorker.new, clock: -> { clock }, probe: -> { true })
ping.communications_channel = channel
announcement = -> { ping.send(:communications_announcement) }

assert(announcement.call == 'P2P with Bob: 24 ms. P2P with Watcher: 6 ms.', 'Direct RTT or participant mapping is wrong')
assert(!announcement.call.include?('Unrelated'), 'Ping exposed a non-roster participant')
bob.last_pong = 0.0
expected = 'Communications: mixed P2P and relay connections. P2P with Watcher: 6 ms. Communications via relay: Bob. Communications UDP relay ping: 15 ms.'
assert(announcement.call == expected, 'Expired direct path reused old peer RTT or failed to explain mixed mode')
udp = false
assert(announcement.call.end_with?('Communications UDP relay ping is unavailable.'), 'TCP fallback reported stale UDP RTT')
assert(announcement.call.include?('P2P with Watcher: 6 ms.'), 'Missing relay UDP discarded a valid direct RTT')
udp = true
native_state[:active] = false # participant limit / server policy
assert(announcement.call == 'Communications via relay: Bob, Watcher. Communications UDP relay ping: 15 ms.', 'Configured P2P misreported as active')
native_state[:active] = true
bob.last_pong = clock
[nil, -0.001, Float::INFINITY, Float::NAN, '0.02'].each do |rtt|
  bob.rtt = rtt
  assert(announcement.call.start_with?('P2P with Bob: ping is unavailable.'), 'Invalid direct RTT presented as a measured ping')
end
bob.rtt = 0.0
assert(announcement.call.start_with?('P2P with Bob: 0 ms.'), 'Valid direct zero RTT rejected')
paths.instance_variable_set(:@failed, true)
assert(announcement.call.start_with?('Communications via relay: Bob, Watcher.'), 'Failed native P2P still reported direct')
paths.instance_variable_set(:@failed, false)
native_state[:participants].delete(1)
session.participants.delete_if { |p| p.id == 1 }
assert(announcement.call == 'P2P with Watcher: 6 ms.', 'Departed participant retained')
assert(session.sent.empty? && session.invites.empty? && program.endpoints.size == 1 && work.operation.nil?, 'Ping sent packets or created resources')
channel.reconnect
assert(announcement.call.nil?, 'Reconnecting channel exposed stale direct RTT')
channel.close
assert(announcement.call.nil?, 'Closed channel exposed direct RTT')
puts 'PASS direct/relay/mixed ping: native freshness and policy, actual participants, invalid/stale samples, no I/O, lifecycle'
