require_relative "../../support/realtime_channel"
require_relative "../../../lib/realtime/event_channel"

now = 0.0
members = %w[Alice Bob Carol Dave Watcher]
work = ChannelWork.new
program = ChannelProgram.new('Bob')
channel = GameRoomRealtime::EventChannel.new(program: program, match: 'doubles', owner: 'Alice', viewer: 'Bob',
  clock: -> { now }, members: -> { members }, work: work, event_work: ChannelWork.new)
channel.enable_events('pong-doubles-1')
channel.tick; work.finish; channel.tick
endpoint = program.endpoints.first
session = ChannelSession.new('doubles-session', 'Bob', members)
def session.on_reliable(&block); @event_receiver = block; end
def session.deliver_event(user, data)
  @event_receiver.call(ChannelMessage.new(ChannelParticipant.new(99, user), data))
end
metadata = {'gr_realtime' => 1, 'match' => 'doubles', 'events' => 'pong-doubles-1'}
old = ChannelInvitation.new(session, metadata: metadata.merge('events' => 'pong-local-1'))
endpoint.deliver(old); channel.tick
assert(old.accepts.zero? && !work.operation, 'doubles accepted an old singles event dialect')
good = ChannelInvitation.new(session, metadata: metadata)
endpoint.deliver(good); channel.tick; work.finish; channel.tick
assert(channel.connected? && good.accepts == 1, 'matching doubles invitation did not connect')
packet = ->(n, epoch = channel.epoch) {
  GameRoomRealtime::Protocol.encode(match: 'doubles', epoch: epoch, sequence: n, kind: 'event', body: {'action' => 'serve'})
}
session.deliver_event('Carol', packet.call(1))
session.deliver_event('Mallory', packet.call(1))
session.deliver_event('Alice', packet.call(1, 'old'))
assert(channel.take_events.empty?, 'doubles bypassed native owner or epoch authorization')
[1, 1, 2].each { |n| session.deliver_event('Alice', packet.call(n)) }
assert(channel.take_events.map { |_, p| p['n'] } == [1, 2], 'doubles reliable ordering or deduplication changed')
channel.close
require_relative "../../support/pong_client"

[%w[Alice Bob Carol Dave], %w[Bob Carol Dave Erin]].each do |players|
  h = PongHarness.new(players: players, options: {'team_size' => 2, 'team_seats' => [0, 0, 1, 1]})
  begin
    assert(h.network.values.all? { |channel| channel.event_protocol == 'pong-doubles-peer-2' },
      'four-client match did not select its separate protocol dialect')
    host = h.clients['Alice']
    h.advance(400, names: h.clients.keys - [players.last])
    assert(host.paused && host.engine.turn.zero?, 'missing fourth participant did not prevent startup')
    h.advance(550)
    assert(h.clients.values.none?(&:paused), 'four participants did not establish the match')
    server = players[host.engine.server]
    h.press(server)
    h.advance(6)
    assert(players.all? { |name| h.clients[name].engine.turn == 1 }, 'doubles serve was not relayed to every participant')
    receiver = host.engine.rotation.hitter(1)
    teammate = (host.engine.rotation.members(host.engine.rotation.team(receiver)) - [receiver]).first
    forged = {'action' => 'hit', 'side' => receiver, 'turn' => 2, 'r' => 0,
      'ball' => host.engine.ball.merge('dy' => host.engine.rotation.team(receiver).zero? ? 1 : -1)}
    inbox = h.network['alice'].event_inbox
    inbox << [players[teammate].downcase, {'d' => forged}]
    inbox << [players[teammate].downcase, {'d' => forged.merge('side' => teammate)}]
    inbox << ['watcher', {'d' => forged}]
    inbox << [players[receiver].downcase, {'d' => forged.merge('turn' => 4)}]
    inbox << [players[receiver].downcase, {'d' => forged.merge('r' => -1)}]
    host.send(:receive_peer_events)
    assert(host.engine.turn == 1, 'wrong native actor, teammate, observer, stale or wrong-turn event changed the rally')
    4.times do |index|
      seat = host.engine.rotation.hitter(host.engine.turn)
      actor = h.clients[players[seat]]
      actor.engine.ball.merge!('x' => actor.engine.paddles[seat],
        'y' => host.engine.rotation.team(seat).zero? ? 3.0 : 17.0)
      h.press(players[seat])
      h.advance(6)
      assert(players.all? { |name| h.clients[name].engine.turn == index + 2 },
        "return by participant #{seat} did not follow the doubles rotation")
    end
    loser = host.engine.rotation.hitter(host.engine.turn)
    h.clients[players[loser]].engine.ball.merge!('x' => 1.0,
      'y' => host.engine.rotation.team(loser).zero? ? 0.1 : 19.9)
    h.network[players.last.downcase].drop = true
    h.network['watcher'].connected = false
    h.advance(12)
    assert(host.engine.goal != nil && host.context_data['pong_point'] == nil,
      'a point was committed without the fourth participant acknowledgement')
    h.network[players.last.downcase].drop = false
    h.advance(12)
    value = "0:#{1 - host.engine.rotation.team(loser)}"
    assert(host.context_data['pong_point'] == value, 'four humans could not agree a point without an observer')
    context = GameRoomGames::ActionContext.new(table_owner: 'Alice', local_data: host.context_data)
    status, = h.rules.action_for({'kind' => 'command', 'action' => 'pong_point', 'point' => value},
      h.replay, 'Alice', context: context)
    assert(status == :ok, 'agreed doubles point did not use the durable game action path')
    h.network.each_value { |entry| entry.epoch = 'replacement' }
    h.advance(12)
    assert(host.context_data['pong_point'] == value && host.engine.goal != nil,
      'reconnect discarded an agreed pending point or restarted its rally')
    h.accept_point(value)
    h.advance(380)
    assert(host.context_data['pong_point'] == nil && host.engine.turn.zero? && h.replay.state[:rally] == 1,
      'durable confirmation duplicated the point or replayed the old service')
    future_rotation = GameRoomPong::Rotation.new(teams: [0, 0, 1, 1], rally: 2, first_server: host.send(:first_server))
    future_engine = GameRoomPong::PeerEngine.new(side: future_rotation.server, authority: false,
      teams: [0, 0, 1, 1], rally: 2, first_server: host.send(:first_server))
    assert(future_engine.strike(future_rotation.server), 'future doubles serve fixture failed')
    future = future_engine.take_transition.merge('r' => 2)
    h.network['alice'].event_inbox << [players[future_rotation.server].downcase, {'d' => future}]
    host.send(:receive_peer_events)
    assert(host.engine.turn.zero? && host.send(:rally_state).deferred_events.length == 1,
      'next-rally doubles serve was lost or applied before the durable point')
    h.accept_point('1:0')
    host.send(:receive_peer_events)
    assert(host.engine.turn == 1 && host.send(:rally_state).deferred_events.empty?,
      'deferred doubles serve did not resume after durable confirmation')
    host.send(:receive_peer_events)
    assert(host.engine.turn == 1, 'deferred doubles serve was applied twice')
  ensure
    h.close
  end
end
class DoublesNativeSession < ChannelSession
  attr_reader :reliable_sent
  def initialize(network, viewer, names)
    super('native-doubles-four', viewer, names)
    @network, @viewer, @reliable_sent = network, viewer, []
    network[viewer] = self
  end
  def on_reliable(&block); @event_receiver = block; end
  def deliver_event(user, data)
    @event_receiver.call(ChannelMessage.new(ChannelParticipant.new(99, user), data))
  end
  def send_unreliable(data, to:)
    super
    to.each { |target| @network.fetch(target.user).deliver(@viewer, data) }
  end
  def send_reliable(data, to:)
    @reliable_sent << data
    to.each { |target| @network.fetch(target.user).deliver_event(@viewer, data) }
    Struct.new(:results).new(to.to_h { |target| [target, :delivered] })
  end
end

h = PongHarness.new(players: %w[Alice Bob Carol Dave], options: {'team_size' => 2, 'team_seats' => [0, 0, 1, 1]})
begin
  sessions, workers = {}, []
  names = h.clients.keys
  names.each { |name| DoublesNativeSession.new(sessions, name, names) }
  h.clients.each do |name, client|
    h.network[name.downcase].close
    worker_factory = -> { worker = ChannelWork.new; workers << worker; worker }
    native = GameRoomRealtime::EventChannel.new(program: ChannelProgram.new(name), match: client.instance_variable_get(:@match),
      owner: 'Alice', viewer: name, clock: -> { h.now }, members: -> { names },
      work_factory: worker_factory, event_work_factory: worker_factory)
    native.enable_events('pong-doubles-peer-2', routing: :peers)
    native.instance_variable_set(:@endpoint, ChannelEndpoint.new(name))
    native.__send__(:attach, sessions.fetch(name))
    client.instance_variable_set(:@channel, native)
    client.before_wait(h.replay, name)
    h.network[name.downcase] = native
  end
  advance = ->(count) { count.times { workers.each { |worker| worker.finish if worker.operation }; h.advance(1) } }
  advance.call(550)
  host = h.clients['Alice']
  assert(h.clients.values.none?(&:paused), 'four clients failed over real EventChannel instances')
  h.press(h.players[host.engine.server])
  advance.call(12)
  4.times do |index|
    seat = host.engine.rotation.hitter(host.engine.turn)
    actor = h.clients[h.players[seat]]
    actor.engine.ball.merge!('x' => actor.engine.paddles[seat], 'y' => host.engine.rotation.team(seat).zero? ? 3.0 : 17.0)
    h.press(h.players[seat])
    advance.call(12)
    assert(h.players.all? { |name| h.clients[name].engine.turn == index + 2 }, 'native reliable four-client rally diverged')
  end
  loser = host.engine.rotation.hitter(host.engine.turn)
  h.clients[h.players[loser]].engine.ball.merge!('x' => 1.0,
    'y' => host.engine.rotation.team(loser).zero? ? 0.1 : 19.9)
  advance.call(30)
  assert(host.context_data['pong_point'] == "0:#{1 - host.engine.rotation.team(loser)}",
    'native four-client acknowledgement did not produce a durable point proposal')
  packets = sessions.values.flat_map { |entry| entry.sent.map(&:first) + entry.reliable_sent }
  assert(packets.all? { |data| data.bytesize <= GameRoomRealtime::Protocol::MAX_BYTES }, 'expanded native packet exceeded 1100 bytes')
  assert(packets.any? { |data| JSON.parse(data).dig('d', 'state', 'p')&.length == 4 }, 'packet cap test did not carry four paddles')
  expanded = host.engine.snapshot
  expanded['tick'] = 2**40
  expanded['edges'] = Array.new(4, 2**31 - 1)
  expanded['fx'] = Array.new(8) { |index| [2**40 + index, 'shield_hit', index % 4, 29.999, -999.999] }
  expanded['b'].merge!('speed' => 999.999, 'lateral' => 0.999, 'x' => 29.999, 'y' => -999.999)
  body = {'r' => 2**31 - 1, 'local' => 1, 'turn' => 2**31 - 1, 'goal' => 1,
    'paused' => true, 'ready' => true, 'ready_in' => 9.999, 'serve_wait' => false, 'state' => expanded}
  expanded_packet = GameRoomRealtime::Protocol.encode(match: host.instance_variable_get(:@match), epoch: h.network['alice'].epoch,
    sequence: GameRoomRealtime::Protocol::MAX_SEQUENCE, ack: GameRoomRealtime::Protocol::MAX_SEQUENCE, kind: 'state', body: body)
  assert(expanded_packet.bytesize <= 1100, 'four-paddle snapshot with eight effects exceeded the unchanged packet cap')
  puts "PASS four-client EventChannel rally and point: #{packets.length} native-stub packets, maximum #{packets.map(&:bytesize).max}/1100; expanded boundary #{expanded_packet.bytesize}/1100 bytes"
ensure
  h.close
end
puts 'PASS Pong doubles network: dialect, authentication, ordered events, readiness, acknowledgements and reconnect'
