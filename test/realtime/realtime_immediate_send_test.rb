require_relative "../support/realtime_channel"
require_relative "../../lib/realtime/event_channel"

class ImmediateEventSession < ChannelSession
  attr_reader :reliable_sent
  attr_accessor :delivery_result

  def on_reliable(&block); @event_receiver = block; end

  def send_reliable(data, to:)
    (@reliable_sent ||= []) << [data, to.map(&:user)]
    @delivery_result || Struct.new(:results).new(to.to_h { |target| [target, :delivered] })
  end
end

class ImmediateEventRig
  attr_reader :channel, :session, :worker
  attr_accessor :now

  def initialize(worker: ChannelWork.new)
    @now = 1.0
    @worker = worker
    @channel = GameRoomRealtime::EventChannel.new(program: ChannelProgram.new('Alice'),
      match: 'immediate', owner: 'Alice', viewer: 'Alice', clock: -> { @now },
      members: -> { %w[Alice Bob Carol] }, work: ChannelWork.new, event_work: @worker)
    @channel.enable_events('immediate-test', routing: :peers)
    @channel.required_members = %w[Bob Carol]
    @session = ImmediateEventSession.new('immediate-session', 'Alice', %w[Alice Bob Carol])
    # Only bypass asynchronous endpoint setup; the reliable lane and workers
    # below are the real production objects. There is no live native endpoint.
    @channel.instance_variable_set(:@endpoint, ChannelEndpoint.new('Alice'))
    @channel.__send__(:attach, @session)
  end

  def packet(number)
    GameRoomRealtime::Protocol.encode(match: 'immediate', epoch: @channel.epoch,
      sequence: number, kind: 'event', body: { 'action' => 'hit' })
  end

  def close; @channel.close; end
end

rig = ImmediateEventRig.new
begin
  first = rig.packet(1)
  assert(rig.channel.send_event(first), 'valid reliable action refused')
  assert(rig.worker.operation, 'idle reliable lane waited for the next UI tick before starting its worker')
  assert(rig.session.reliable_sent == nil, 'native reliable send executed in the UI caller')
  rig.worker.finish # Background work runs with no channel tick in between.
  assert(rig.session.reliable_sent == [[first, %w[Bob Carol]]], 'first action was not sent without a UI tick')
  rig.now += 0.05
  second = rig.packet(2)
  assert(rig.channel.send_event(second), 'second action refused after worker completion')
  assert(rig.worker.operation, 'completed worker result added another UI-tick delay')
  rig.worker.finish
  assert(rig.session.reliable_sent.map(&:first) == [first, second], 'immediate sends lost ordering')
ensure
  rig.close
end

puts 'PASS immediate reliable scheduling: no next-UI-tick wait, native RPC remains background, completed result retained'

# Several actions within one UI frame remain FIFO. A new call can collect the
# previous worker result, but it may never overtake an older queued action.
rig = ImmediateEventRig.new
begin
  packets = (1..4).map { |n| rig.packet(n) }
  packets.first(3).each { |packet| assert(rig.channel.send_event(packet), 'burst action refused') }
  assert(rig.session.reliable_sent == nil, 'burst bypassed the finite background worker')
  rig.worker.finish
  rig.channel.send_event(packets.last)
  rig.worker.finish
  2.times { rig.channel.tick; rig.worker.finish }
  rig.channel.tick
  assert(rig.session.reliable_sent.map(&:first) == packets, 'burst reordered or repeated a reliable action')
  assert(rig.channel.instance_variable_get(:@deliveries).empty?, 'completed Delivery results were lost')
ensure
  rig.close
end

# Membership can change after scheduling but before a worker actually runs.
rig = ImmediateEventRig.new
begin
  first, second = rig.packet(1), rig.packet(2)
  rig.channel.send_event(first)
  carol = rig.session.participants.last
  rig.session.participants.delete(carol)
  rig.worker.finish
  rig.channel.send_event(second)
  assert(!rig.worker.operation && rig.session.reliable_sent == nil, 'partial membership bypassed required recipient')
  rig.session.participants << carol
  rig.channel.tick
  rig.worker.finish
  rig.channel.tick
  rig.worker.finish
  rig.channel.tick
  assert(rig.session.reliable_sent == [[first, %w[Bob Carol]], [second, %w[Bob Carol]]], 'membership retry lost FIFO or duplicated an action')
ensure
  rig.close
end

# A delivery failure discovered while scheduling another action must trigger
# recovery, not discard the failure or report the newly invalidated action as
# successfully accepted. The previous Delivery is still inspected.
rig = ImmediateEventRig.new
begin
  targets = rig.session.participants.reject { |p| p.user == 'Alice' }
  rig.session.delivery_result = Struct.new(:results).new(targets.to_h { |p| [p, :failed] })
  first = rig.packet(1)
  rig.channel.send_event(first)
  rig.worker.finish
  assert(!rig.channel.send_event(rig.packet(2)), 'failed delivery was hidden by immediate scheduling')
  assert(rig.channel.instance_variable_get(:@reconnect_reason) == 'ReliableDeliveryFailed', 'delivery failure did not retain its recovery reason')
  assert(rig.session.reliable_sent.map(&:first) == [first] && !rig.worker.operation, 'new action started on a failed generation')
ensure
  rig.close
end

# Bounded work during a stalled RPC: one in flight, at most LIMIT queued.
rig = ImmediateEventRig.new
begin
  rig.channel.send_event(rig.packet(1))
  GameRoomRealtime::EventChannel::LIMIT.times do |i|
    assert(rig.channel.send_event(rig.packet(i + 2)), 'bounded queue rejected an in-limit action')
  end
  assert(!rig.channel.send_event(rig.packet(999)), 'burst exceeded the bounded outbox')
  assert(rig.channel.instance_variable_get(:@reconnect_reason) == 'ReliableOutboxFull', 'overflow did not request recovery')
  rig.worker.finish
  assert(rig.session.reliable_sent == nil, 'cancelled, not-yet-executed worker sent an old-generation action')
ensure
  rig.close
end

puts 'PASS immediate send safety: burst FIFO, required-member race, delivery failure, bounded queue, cancelled generation'

[:close, :reconnect].each do |operation|
  rig = ImmediateEventRig.new
  begin
    rig.channel.send_event(rig.packet(1))
    rig.channel.public_send(operation)
    assert(!rig.channel.send_event(rig.packet(2)), 'closed/recovering channel accepted a new action')
    rig.worker.finish
    assert(rig.session.reliable_sent == nil, "write began after #{operation}")
  ensure
    rig.close
  end
end

# Real worker threads (still fake native I/O): a blocked send must not block
# send_event, and repeated UI calls must not spawn concurrent reliable RPCs.
require 'timeout'
worker = GameRoomBackground::Work.new
rig = ImmediateEventRig.new(worker: worker)
ui_thread, calls, release = Thread.current, Queue.new, Queue.new
active, maximum_active = 0, 0
rig.session.define_singleton_method(:send_reliable) do |data, to:|
  active += 1
  maximum_active = [maximum_active, active].max
  calls << [Thread.current, data]
  release.pop
  Struct.new(:results).new(to.to_h { |target| [target, :delivered] })
ensure
  active -= 1
end
begin
  Timeout.timeout(3) do
    first, second = rig.packet(1), rig.packet(2)
    assert(rig.channel.send_event(first), 'real worker refused first action')
    thread, packet = calls.pop
    assert(thread != ui_thread && packet == first, 'reliable RPC ran on the caller thread or sent wrong action')
    assert(rig.channel.send_event(second), 'real worker refused queued action')
    10.times { rig.channel.tick }
    assert(calls.empty? && active == 1, 'blocked RPC spawned a second concurrent send')
    release << true
    while calls.empty?
      rig.channel.tick
      sleep(0.001)
    end
    thread, packet = calls.pop
    assert(thread != ui_thread && packet == second, 'real worker lost FIFO')
    release << true
    while worker.busy?
      rig.channel.tick
      sleep(0.001)
    end
    assert(maximum_active == 1, 'reliable lane exceeded one active worker')
  end
ensure
  2.times { release << true }
  rig.close
end

puts 'PASS close/reconnect cancellation and real threaded send: caller remains free, single active RPC, FIFO, cleanup'
