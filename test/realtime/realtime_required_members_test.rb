require_relative "../support/realtime_event_channel"

# A temporarily missing required recipient is not an empty successful delivery.
now = 0.0
work, sends, program = ChannelWork.new, ChannelWork.new, ChannelProgram.new('Alice')
channel = GameRoomRealtime::EventChannel.new(program: program, match: 'required', owner: 'Alice', viewer: 'Alice',
  clock: -> { now }, members: -> { %w[Alice Bob Carol Watcher] }, work: work, event_work: sends)
channel.enable_events
channel.required_members = %w[Bob Carol]
channel.tick; work.finish; channel.tick; work.finish; channel.tick
session = channel.instance_variable_get(:@session)
bob, carol = ChannelParticipant.new(1, 'Bob'), ChannelParticipant.new(2, 'Carol')
session.participants << bob
packet = GameRoomRealtime::Protocol.encode(match: 'required', epoch: channel.epoch,
  sequence: 1, kind: 'event', body: {'action' => 'serve'})
assert(channel.send_event(packet), 'bounded pending action was refused')
channel.tick
sends.finish if sends.operation
channel.tick
assert(session.reliable_sent.to_a.empty?, 'required recipient omitted: a partial recipient list was sent as success')
now = 0.4
session.participants << carol
channel.tick
sends.finish if sends.operation
channel.tick
assert(session.reliable_sent == [[packet, %w[Bob Carol]]], 'queued action was not sent once to every required player on return')
assert(!channel.instance_variable_get(:@reconnect_requested), 'short membership gap needlessly replaced a healthy session')
channel.close
puts 'PASS required recipients: missing player retained, short return delivers once, observer not required'

[:worker_membership_race, :missing_delivery_status, :missing_delivery_result, :absence_deadline].each do |scenario|
  now = 0.0
  work, sends, program = ChannelWork.new, ChannelWork.new, ChannelProgram.new('Alice')
  channel = GameRoomRealtime::EventChannel.new(program: program, match: 'required', owner: 'Alice', viewer: 'Alice',
    clock: -> { now }, members: -> { %w[Alice Bob Carol Watcher] }, work: work, event_work: sends)
  channel.enable_events
  channel.required_members = %w[Bob Carol]
  channel.tick; work.finish; channel.tick; work.finish; channel.tick
  session = channel.instance_variable_get(:@session)
  session.participants << bob << carol
  packet = GameRoomRealtime::Protocol.encode(match: 'required', epoch: channel.epoch,
    sequence: 1, kind: 'event', body: {'action' => 'serve'})
  session.participants.delete(carol) if scenario == :absence_deadline
  if scenario == :missing_delivery_status
    session.define_singleton_method(:send_reliable) do |_data, to:|
      Struct.new(:results).new(to.reject { |p| p.user == 'Carol' }.to_h { |p| [p, :delivered] })
    end
  elsif scenario == :missing_delivery_result
    session.define_singleton_method(:send_reliable) { |_data, to:| nil }
  end
  channel.send_event(packet)
  channel.tick
  if scenario == :worker_membership_race
    session.participants.delete(carol)
    sends.finish
    channel.tick
    assert(session.reliable_sent.to_a.empty?, 'worker sent to a stale partial membership')
    session.participants << ChannelParticipant.new(22, 'Carol')
    channel.tick; sends.finish; channel.tick
    assert(session.reliable_sent == [[packet, %w[Bob Carol]]], 'native membership race lost or duplicated the queued action')
  elsif scenario == :missing_delivery_result
    sends.finish; channel.tick
    assert(channel.instance_variable_get(:@reconnect_reason) == 'MissingReliableDeliveryResult', 'missing native Delivery object was treated as success')
  else
    sends.finish if sends.operation
    channel.tick
    assert(!channel.instance_variable_get(:@reconnect_requested), 'short pending delivery failed prematurely')
    # Complete unrelated invitation work; the deadline below is specifically
    # for the required reliable recipient, not a hung fixture invitation RPC.
    10.times do
      break unless work.operation
      work.finish
      channel.tick
    end
    now = 8.2
    channel.tick
    assert(channel.instance_variable_get(:@reconnect_requested), "unresolved required player silently succeeded: #{scenario}")
  end
  channel.close
end
puts 'PASS membership at worker execution, current recipient IDs, missing acknowledgement, bounded absence timeout'
