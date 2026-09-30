require_relative "../../lib/realtime/metrics"
def assert(value, message); raise message unless value; end
module Log
  def self.lines; @lines ||= []; end
  def self.debug(message); lines << message; end
end
now = 0.0
endpoint = Object.new
def endpoint.closed?; false; end
def endpoint.latency; 0.025; end
def endpoint.fast_path?; true; end
metrics = GameRoomRealtime::Metrics.new(clock: -> { now })
metrics.observe(:queue_wait, 0.008)
metrics.observe(:send_rpc, 0.123)
metrics.observe(:receive_wait, 0.016)
1000.times do
  now += 0.008
  metrics.tick(endpoint: endpoint, role: 'guest', generation: 2)
end
assert(Log.lines.empty?, 'metrics performed per-frame logging')
now = 10.1
metrics.tick(endpoint: endpoint, role: 'guest', generation: 2)
line = Log.lines.fetch(0)
assert(line.include?('relay_udp_rtt_ms=25') && line.include?('send_rpc_max_ms=123') &&
  line.include?('queue_wait_max_ms=8') && line.include?('receive_wait_max_ms=16'), 'separate latency measures lost their meanings')
def endpoint.fast_path?; false; end
now = 20.2
metrics.tick(endpoint: endpoint, role: 'guest', generation: 2)
assert(Log.lines.last.include?('relay_udp_rtt_ms=unavailable'), 'stale UDP RTT presented as current TCP ping')
assert(Log.lines.last.include?('send_rpc_max_ms=unavailable'), 'metrics reused an old reporting window')
puts 'PASS sparse diagnostics: cached relay RTT, distinct RPC/queue/UI durations, no extra network calls or per-frame logging'
