require_relative 'support/host_source'
require_relative '../lib/realtime/p2p_options'
require EltenTestHost.file('src/eapi/communication.rb')

def assert(value, message); raise message unless value; end

# Actual public Endpoint -> Relay::Client -> serialized RPC. Only the final
# network request and session registry are replaced; no sockets or accounts.
class P2PNativeRelay < EltenLink::Relay::Client
  attr_reader :requests
  def initialize
    @features, @requests = ['p2p_v1'], []
    @reliable_send_mutex = Mutex.new
  end
  def request(type, fields)
    @requests << [type, fields]
    fields.merge('id' => 'p2p-test', 'revision' => 1, 'epoch' => 1, 'self_id' => '0', 'owner_id' => '0',
      'key' => Base64.strict_encode64('x' * 24), 'participants' => [{'id' => '0', 'user' => 'Alice'}])
  end
end

class P2PNativeEndpoint < EltenAPI::Communication::Endpoint
  def initialize(relay); @relay = relay; end
  def store_session(data); EltenAPI::Communication::Session.new(self, data); end
end

[{}, {'p2p_enabled' => true}, {'p2p_enabled' => true, 'p2p_participants_limit' => 12},
 {'p2p_enabled' => true, 'p2p_participants_limit' => 0}].each do |options|
  relay = P2PNativeRelay.new
  requested = GameRoomRealtime::P2POptions.session_options(options)
  session = P2PNativeEndpoint.new(relay).create_session(metadata: {'match' => 'table'}, capacity: 32,
    public: false, encryption: 192, **requested)
  expected_mode = requested.fetch(:p2p, :off)
  expected_limit = requested.fetch(:p2p_participants_limit, 2)
  method, payload = relay.requests.last
  assert(method == 'create_session' && payload['p2p'] == expected_mode.to_s && payload['p2p_participants_limit'] == expected_limit,
    'actual host serialized different P2P settings')
  assert(payload['public'] == false && payload['encryption'] == 192 && payload['capacity'] == 32, 'P2P weakened native session')
  assert(session.p2p == expected_mode && session.p2p_participants_limit == expected_limit, 'native session did not retain settings')
end

# Native participant-limit calculation includes spectators; zero is unlimited.
# Disable only worker/socket startup, not the native snapshot logic.
transport = EltenLink::Relay::P2PTransport.allocate
transport.instance_variable_set(:@mutex, Mutex.new)
transport.instance_variable_set(:@sessions, {})
transport.define_singleton_method(:start) { }
[[8, 8, true], [9, 8, false], [32, 0, true]].each_with_index do |(count, limit, active), epoch|
  transport.track('id' => 'native-limit', 'epoch' => epoch, 'p2p' => 'full', 'self_id' => '0',
    'p2p_participants_limit' => limit, 'participants' => count.times.map { |i| {'id' => i.to_s} })
  actual = transport.instance_variable_get(:@sessions).fetch('native-limit')
  assert(actual[:active] == active && actual[:mode] == 'full', 'native participant limit semantics changed')
end

# The native relay owns route selection/fallback for both lanes. A mixed
# P2P/relay path must not resend unreliable payloads to already-direct peers.
paths = Object.new
direct_reliable, remaining = false, nil
direct_calls, relay_calls = [], []
paths.define_singleton_method(:reliable?) { |_session| direct_reliable }
paths.define_singleton_method(:send_reliable) { |**args| direct_calls << args; :direct }
paths.define_singleton_method(:send_unreliable) { |**_args| remaining }
relay = P2PNativeRelay.new
relay.instance_variable_set(:@p2p, paths)
relay.define_singleton_method(:send_relay_reliable) { |**args| relay_calls << [:reliable, args]; :relay }
relay.define_singleton_method(:send_relay_unreliable) { |**args| relay_calls << [:unreliable, args]; true }
data = {session_id: 'match', epoch: 1, message_id: 1, targets: %w[Bob Watcher], envelope: 'message'}
assert(relay.send_reliable(**data) == :relay, 'unavailable P2P stopped reliable relay')
direct_reliable = true
assert(relay.send_reliable(**data) == :direct && direct_calls == [data], 'full P2P ignored reliable lane')
direct_reliable = false
assert(relay.send_reliable(**data) == :relay, 'lost P2P did not fall back')
relay.send_unreliable(**data)
assert(relay_calls.last == [:unreliable, data], 'unavailable P2P stopped state updates')
remaining = ['Watcher']
relay.send_unreliable(**data)
assert(relay_calls.last == [:unreliable, data.merge(targets: ['Watcher'])], 'mixed route duplicated direct updates')
remaining = []
count = relay_calls.length
assert(relay.send_unreliable(**data) && relay_calls.length == count, 'direct update was also relayed')
puts 'PASS native ELTEN P2P: API keywords, wire fields, full mode, participant limits and relay fallback delegation (no network)'
