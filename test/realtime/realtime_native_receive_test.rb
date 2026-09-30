require_relative "../support/host_source"
require_relative "../support/realtime_receive_poll"

# Actual ELTEN Session/EventQueue, with only endpoint I/O replaced. No account,
# connection, loop pumping, source rewriting or changes to native queue limits.
source = ARGV[0] || EltenTestHost.file("src/eapi/communication.rb")
abort 'Provide current ELTEN src/eapi/communication.rb' unless File.file?(source)
require source

class NativeQueueEndpoint < ChannelEndpoint
  attr_reader :user, :callbacks, :errors
  def initialize(user)
    super
    @user, @callbacks, @errors = user, [], []
  end
  def enqueue_callback(callback, *args); @callbacks << [callback, args]; end
  def dispatch
    callbacks, @callbacks = @callbacks, []
    callbacks.each { |callback, args| callback.call(*args) }
  end
  def wait_step(**_args); raise 'native receive pumped/waited on the UI'; end
  def record_error(error); @errors << error; end
  def session_closed(*_args, **_options); end
end

time = 0.0
endpoint = NativeQueueEndpoint.new('Alice')
session = EltenAPI::Communication::Session.new(endpoint, {
  'id' => 'native-memory-only', 'revision' => 1, 'owner_id' => '0', 'self_id' => '0',
  'capacity' => 4, 'encryption' => 192, 'key' => Base64.strict_encode64('x' * 24), 'epoch' => 1,
  'participants' => %w[Alice Bob].each_with_index.map { |u, i| {'id' => i.to_s, 'user' => u} }
})
channel = GameRoomRealtime::EventChannel.new(program: ChannelProgram.new('Alice'), match: 'native',
  owner: 'Alice', viewer: 'Alice', clock: -> { time }, members: -> { %w[Alice Bob] },
  work: ChannelWork.new, event_work: ChannelWork.new)
channel.enable_events('native-poll', routing: :peers)
channel.instance_variable_set(:@endpoint, endpoint)
channel.__send__(:attach, session)
send_packet = ->(kind, n) {
  data = GameRoomRealtime::Protocol.encode(match: 'native', epoch: channel.epoch, sequence: n,
    kind: kind == :reliable ? 'event' : 'input', body: {'action' => 'hit'})
  msg = EltenAPI::Communication::Message.new(sender: session.participant('1'), data: data, id: n, kind: kind)
  assert(session.deliver(kind, msg), 'actual native queue refused a valid message')
}
send_packet.call(:reliable, 1)
send_packet.call(:unreliable, 1)
channel.tick
assert(channel.take_events.length == 1 && channel.take_packets.length == 1, 'native queue did not reach the game')
assert(endpoint.callbacks.length == 2, 'poll unexpectedly dispatched callbacks/UI')
endpoint.dispatch
assert(channel.take_events.empty? && channel.take_packets.empty?, 'native callbacks replayed consumed data')

# Prolonged play with callback-first and poll-first frames must not grow a
# duplicate native queue. More than two native queue capacities are delivered.
9000.times do |i|
  n = i + 2
  send_packet.call(:unreliable, n)
  send_packet.call(:reliable, n)
  endpoint.dispatch if i.even?
  channel.tick
  assert(channel.take_events.length == 1 && channel.take_packets.length == 1, 'lost or duplicated native delivery')
  endpoint.dispatch
  assert(session.receive(timeout: 0).nil?, 'duplicate native queue grew after a normal frame')
end
assert(endpoint.errors.empty?, 'native queue overflowed during continued play')

# Per-frame work is bounded, and the remainder is processed on the next frame.
(GameRoomRealtime::Channel::RECEIVE_BATCH + 3).times { |i| send_packet.call(:unreliable, 10_000 + i) }
channel.tick
assert(channel.take_packets['bob']['n'] == 10_127, 'poll batch was not bounded')
channel.tick
assert(channel.take_packets['bob']['n'] == 10_130, 'bounded poll lost the remaining messages')
endpoint.dispatch
assert(channel.take_packets.empty?, 'callbacks repeated the batched positions')
endpoint.define_singleton_method(:limit) { |_name| 0 }
begin
  channel.send('rejected by the native size validator')
  raise 'native payload rejection was swallowed'
rescue EltenAPI::Communication::MessageTooLarge => error
  assert(channel.internal_error.equal?(error), 'native payload rejection was classified as a disconnection')
  assert(error.backtrace.any? { |line| line.include?('communication.rb') && line.include?('validate_size!') },
    'payload regression did not exercise the actual native validator')
end
channel.close
puts 'PASS actual ELTEN receive: no waits/RPC/UI pumping, 18000 mixed messages, bounded draining, callback dedup and native payload rejection'
