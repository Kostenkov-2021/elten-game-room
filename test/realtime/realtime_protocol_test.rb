require_relative "../../lib/realtime/protocol"
def assert(value, message); raise message unless value; end
protocol = GameRoomRealtime::Protocol
packet = protocol.encode(match: 'gameA', epoch: 'channelA', sequence: 10, kind: 'input', body: {'move' => 1})
parsed = protocol.decode(packet, match: 'gameA', epoch: 'channelA')
assert(parsed['d']['move'] == 1, 'roundtrip')
assert(protocol.decode(packet, match: 'gameB', epoch: 'channelA') == nil, 'cross-game packet')
assert(protocol.decode(packet, match: 'gameA', epoch: 'channelB') == nil, 'old generation')
['', '{', '[]', 'null', 'x' * 1201, '{"v":NaN}', "\xff".b].each do |bad|
  assert(protocol.decode(bad, match: 'gameA', epoch: 'channelA') == nil, 'malformed packet')
end
peer = GameRoomRealtime::PeerState.new
assert(peer.receive(parsed, now: 4.0, last_sent: 20), 'first packet')
assert(!peer.receive(parsed, now: 5.0, last_sent: 20), 'duplicate refreshed heartbeat')
assert(peer.received_at == 4.0 && !peer.fresh?(5.0), 'stale packet kept connection alive')
assert(!peer.receive(parsed.merge('n' => 11, 'a' => 1000), now: 5.0, last_sent: 20), 'future acknowledgement')
assert(peer.receive(parsed.merge('n' => 50, 'a' => 20), now: 5.0, last_sent: 20), 'lost frames prevented recovery')
assert(peer.sequence == 50 && peer.ack == 20, 'latest complete state not selected')
puts 'PASS realtime protocol: loss, duplicates, ordering, generations, malformed input and acknowledgements'
