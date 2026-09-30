require_relative "../support/cases"
require_relative "../support/realtime_event_channel"

module Log
  def self.warning(message); (@warnings ||= []) << message; end
  def self.warnings; @warnings ||= []; end
end

def error_rig
  work, events, program = ChannelWork.new, ChannelWork.new, ChannelProgram.new('Alice')
  channel = GameRoomRealtime::EventChannel.new(program: program, match: 'match', owner: 'Alice', viewer: 'Alice',
    clock: GameRoomTest::Clock.new, members: -> { %w[Alice Bob] }, work: work, event_work: events)
  channel.enable_events
  channel.tick; work.finish; channel.tick; work.finish; channel.tick
  session = channel.instance_variable_get(:@session)
  session.participants << ChannelParticipant.new(1, 'Bob')
  [channel, session, work, events, program]
end

[:send_unreliable, :send_reliable, :receive].each do |method|
  channel, session, work, events, program = error_rig
  calls = 0
  fault = NoMethodError.new("broken #{method}")
  fault.set_backtrace(['original_operation.rb:42'])
  session.define_singleton_method(method) { |*_, **_| calls += 1; raise fault }
  before = Log.warnings.length
  observed = assert_raises(NoMethodError) do
    case method
    when :send_unreliable then channel.send('packet')
    when :send_reliable
      channel.send_event('packet'); events.finish; channel.tick
    when :receive then channel.tick
    end
  end
  assert(observed.equal?(fault), 'lost original exception')
  assert(channel.internal_error.equal?(fault) && channel.last_exception.equal?(fault), 'fault was not retained')
  3.times { assert(assert_raises(NoMethodError) { channel.tick }.equal?(fault), 'fault replaced') }
  assert(calls == 1 && program.endpoints.length == 1, 'programming error retried or reconnected')
  assert(Log.warnings.length == before + 1 && Log.warnings.last.include?('original_operation.rb:42'), 'missing/duplicate diagnostic')
  channel.close
  assert(program.endpoints.all?(&:closed?), 'fault prevented endpoint cleanup')
end

channel, session, work, events, program = error_rig
network = EltenAPI::Communication::ConnectionError.new('disconnected')
session.define_singleton_method(:send_reliable) { |*_, **_| raise network }
channel.send_event('packet'); events.finish; channel.tick
assert(channel.internal_error.nil? && channel.last_exception.equal?(network), 'native error treated as a program fault')
channel.tick
assert(program.endpoints.first.closed?, 'native failure did not reconnect')
channel.close

[:deliver, :deliver_event].each do |delivery|
  channel, session, work, events, program = error_rig
  fault = TypeError.new('broken native callback')
  calls = 0
  channel.define_singleton_method(:receive_message) { |*| calls += 1; raise fault }
  before = Log.warnings.length
  assert(assert_raises(TypeError) { session.public_send(delivery, 'Bob', 'packet') }.equal?(fault), 'callback lost original error')
  assert_raises(TypeError) { session.public_send(delivery, 'Bob', 'packet') }
  assert_raises(TypeError) { channel.tick }
  assert(calls == 1 && Log.warnings.length == before + 1, 'callback repeated a programming fault')
  channel.close
  session.public_send(delivery, 'Bob', 'stale')
  assert(calls == 1 && program.endpoints.all?(&:closed?), 'old callback was not retired')
end

work, program = ChannelWork.new, ChannelProgram.new('Alice')
fault = TypeError.new('broken endpoint setup')
program.creation_hook = -> { raise fault }
channel = GameRoomRealtime::Channel.new(program: program, match: 'match', owner: 'Alice', viewer: 'Alice',
  clock: GameRoomTest::Clock.new, members: -> { %w[Alice Bob] }, work: work)
channel.tick; work.finish
assert(assert_raises(TypeError) { channel.tick }.equal?(fault), 'setup lost original error')
assert_raises(TypeError) { channel.tick }
assert(!work.busy?, 'fault restarted endpoint setup')
channel.close
[:send_unreliable, :send_reliable].each do |method|
  channel, session, work, events, program = error_rig
  calls = 0
  fault = EltenAPI::Communication::MessageTooLarge.new('payload exceeds the negotiated limit')
  session.define_singleton_method(method) { |*_, **_| calls += 1; raise fault }
  observed = assert_raises(EltenAPI::Communication::MessageTooLarge) do
    if method == :send_unreliable
      channel.send('packet')
    else
      channel.send_event('packet'); events.finish; channel.tick
    end
  end
  assert(observed.equal?(fault) && channel.internal_error.equal?(fault), 'payload error was treated as a disconnection')
  3.times { assert_raises(EltenAPI::Communication::MessageTooLarge) { channel.tick } }
  assert(calls == 1 && program.endpoints.length == 1, 'invalid payload caused a reconnect/retry loop')
  channel.close
end
puts 'PASS realtime internal errors: identity, backtrace, stopped retries, native recovery, payload rejection and cleanup'
