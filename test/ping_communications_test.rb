require_relative 'support/post_233_ping'
require_relative 'support/realtime_channel'
require_relative 'support/pong_client'

now = 0.0
work, program = ChannelWork.new, ChannelProgram.new('Alice')
channel = GameRoomRealtime::Channel.new(program: program, match: 'ping', owner: 'Alice', viewer: 'Alice',
  clock: -> { now }, members: -> { ['Alice'] }, work: work)
assert(channel.ping_sample.nil? && program.endpoints.empty?, 'reading ping created a connection')
channel.tick; work.finish; channel.tick; work.finish; channel.tick
endpoint = program.endpoints.first
session = channel.instance_variable_get(:@session)
udp, latency = true, 0.01269
reads = 0
endpoint.define_singleton_method(:fast_path?) { udp }
endpoint.define_singleton_method(:latency) { reads += 1; raise 'stale UDP latency read' unless udp; latency }

worker = PingManualWorker.new
service = GameRoomPing.new(program, worker: worker, clock: -> { now }, probe: -> { now += 0.042; true })
service.communications_channel = channel
result = lambda do
  service.request(program)
  worker.finish
  service.poll(program)
end
assert(result.call == 'HTTP ping: 42 ms. Communications UDP relay ping: 13 ms.', 'HTTP and relay RTT mixed or wrong units')
assert(reads == 1 && session.sent.empty? && work.operation.nil? && program.endpoints.length == 1,
  'ping sent packets, dispatched callbacks or opened an extra connection')
assert(service.poll(program).nil?, 'combined result was announced twice')

# Native fast_path? already rejects stale probes. In TCP fallback an old UDP
# sample must not be advertised as a current TCP RTT or a ping to another player.
udp = false
assert(result.call == 'HTTP ping: 42 ms. Communications UDP relay ping is unavailable.', 'TCP fallback reused an old UDP RTT')
assert(reads == 1, 'UDP latency read despite expired fast path')
udp = true
[nil, -0.01, Float::NAN, Float::INFINITY, '0.013'].each do |value|
  latency = value
  assert(result.call.end_with?('Communications UDP relay ping is unavailable.'), 'invalid native RTT accepted')
end
latency = 0.0
assert(result.call.end_with?('Communications UDP relay ping: 0 ms.'), 'valid zero duration rejected')
latency = 0.013
session.state = :closed
assert(result.call == 'HTTP ping: 42 ms.', 'closed session retained a ping sample')
session.state = :open
channel.reconnect
assert(result.call == 'HTTP ping: 42 ms.', 'pending reconnect exposed an obsolete RTT')
channel.close
assert(result.call == 'HTTP ping: 42 ms.', 'closed channel retained a ping sample')

source = Object.new
source.define_singleton_method(:ping_sample) { {relay_udp_ms: 17} }
service = GameRoomPing.new(program, worker: worker, clock: -> { now }, probe: -> { raise IOError, 'HTTP offline' })
service.communications_channel = source
assert(result.call == 'HTTP ping is unavailable. Communications UDP relay ping: 17 ms.', 'HTTP failure discarded valid Communications data')
source.define_singleton_method(:ping_sample) { raise IOError, 'relay closed during read' }
assert(result.call == 'HTTP ping is unavailable. Communications ping is unavailable.', 'relay read error escaped to UI')

# Registration uses the program's current live game client, so it works from
# chat, F1 and local settings as well as the playfield. Closing an old client
# must not disconnect the ping reader already registered by its replacement.
h = PongHarness.new(players: %w[Alice Bob Carol Dave], options: {'team_size' => 2})
h.clients.each do |name, client|
  ping = GameRoomPing.for(h.programs.fetch(name))
  assert(ping.communications_channel.equal?(h.network.fetch(name.downcase)), 'active client did not register its channel')
  assert(GameRoomPing.for(h.programs.fetch(name)).equal?(ping), 'duplicate ping service per form')
end
replacement = Object.new
alice_ping = GameRoomPing.for(h.programs.fetch('Alice'))
alice_ping.communications_channel = replacement
h.clients.fetch('Alice').close
assert(alice_ping.communications_channel.equal?(replacement), 'old client removed the new match ping reader')
h.clients.fetch('Bob').close
assert(GameRoomPing.for(h.programs.fetch('Bob')).communications_channel.nil?, 'closed match kept its channel in ping service')
h.close
puts 'PASS HTTP plus cached Communications relay RTT: scope/lifecycle, UDP freshness, no extra I/O, offline and unavailable states'
