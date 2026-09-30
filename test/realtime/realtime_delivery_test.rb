require_relative "../support/realtime_event_channel"

class TestDelivery
  attr_accessor :results
  def initialize(results); @results = results; end
end

[:failed, :pending, :observer, :gap, :stuck].each do |scenario|
  now = 0.0
  work, sends, program = ChannelWork.new, ChannelWork.new, ChannelProgram.new('Alice')
  channel = GameRoomRealtime::EventChannel.new(program: program, match: 'match', owner: 'Alice', viewer: 'Alice',
    clock: -> { now }, members: -> { %w[Alice Bob Watcher] }, work: work, event_work: sends)
  channel.enable_events
  channel.required_members = ['Bob']
  channel.tick; work.finish; channel.tick; work.finish; channel.tick
  session = channel.instance_variable_get(:@session)
  bob, observer = ChannelParticipant.new(1, 'Bob'), ChannelParticipant.new(2, 'Watcher')
  session.participants << bob << observer
  work.finish if work.operation
  channel.tick
  delivery = TestDelivery.new(bob => :pending, observer => :pending)
  session.define_singleton_method(:send_reliable) { |_data, to:| delivery }
  packet = ->(n) { GameRoomRealtime::Protocol.encode(match: 'match', epoch: channel.epoch,
    sequence: n, kind: 'event', body: {'action' => 'hit'}) }
  if scenario == :gap
    session.deliver_event('Bob', packet.call(1))
    channel.take_events
    session.deliver_event('Bob', packet.call(3))
  else
    channel.send_event(packet.call(1)); channel.tick
    sends.finish unless scenario == :stuck
    channel.tick
    case scenario
    when :failed then delivery.results[bob] = :failed
    when :pending, :stuck then now = 8.1
    when :observer
      delivery.results[bob] = :delivered
      delivery.results[observer] = :failed
    end
    channel.tick
  end
  reset = channel.instance_variable_get(:@reconnect_requested)
  assert(scenario == :observer ? !reset : reset, "wrong delivery recovery: #{scenario}")
  channel.close
end

puts 'PASS reliable delivery: returned RPC is not recipient acknowledgement, failures/deadlines/gaps recover, observers do not stop players'
