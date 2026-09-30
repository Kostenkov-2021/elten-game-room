require_relative "../../support/pong_relay"

[[0, 0, 1, 1], [0, 1, 0, 1]].each do |teams|
  rig = PongRelayFixture.new(teams: teams)
  begin
    rig.ready
    h, host = rig.h, rig.h.clients['Alice']
    server = h.players[host.engine.server]
    receiver = h.players[host.engine.rotation.receiver]
    delayed = (h.players - [server, receiver]).first
    rig.one_way = ->(from, to, packet) {
      packet.dig('d', 'action') == 'serve' && from == server && to == delayed ? 0.35 : 0.04
    }
    h.press(server)
    rig.advance(10)
    actor = h.clients.fetch(receiver)
    side = actor.instance_variable_get(:@side)
    assert(actor.engine.turn == 1 && h.clients[delayed].engine.turn == 0, 'did not create cross-sender ordering fixture')
    actor.engine.ball.merge!('x' => actor.engine.paddles[side],
      'y' => actor.engine.rotation.team(side).zero? ? 3.0 : 17.0)
    h.press(receiver)
    rig.advance(12)
    waiting = h.clients[delayed].send(:rally_state).deferred_events
    assert(waiting.any? { |_, packet| packet.dig('d', 'action') == 'hit' }, 'early direct return was dropped instead of deferred')
    rig.advance(60)
    assert(h.clients.values.all? { |c| c.engine.turn == 2 && c.engine.goal == nil }, 'cross-sender serve/return order diverged')
    assert(h.network.values.none? { |c| c.instance_variable_get(:@reconnect_requested) }, 'ordinary in-flight delay triggered a reconnect')
  ensure
    rig.close
  end
end

# Remove the receiver between the actual local serve and its send_event call,
# then restore the same native session. An idle send now starts immediately;
# waiting one more frame before removing membership would be after delivery
# was already addressed. No addressed packet is dropped by this fixture.
rig = PongRelayFixture.new
begin
  rig.ready
  h, host = rig.h, rig.h.clients['Alice']
  server = h.players[host.engine.server]
  missing = h.players[host.engine.rotation.receiver]
  original = rig.sessions.transform_values { |s| s.participants.dup }
  channel = h.network.fetch(server.downcase)
  send_action = channel.method(:send_event)
  removed = false
  channel.define_singleton_method(:send_event) do |data|
    if !removed && JSON.parse(data).dig('d', 'action') == 'serve'
      rig.sessions.each_value { |s| s.participants.reject! { |p| p.user == missing } }
      removed = true
    end
    send_action.call(data)
  end
  h.press(server)
  rig.advance(1)
  assert(removed && h.clients[server].engine.turn == 1, 'serve/membership race was not exercised')
  rig.advance(50, names: h.clients.keys - [missing])
  assert(rig.transmissions.none? { |t| t[:packet].dig('d', 'action') == 'serve' }, 'serve was sent with a reduced required roster')
  rig.sessions.each { |name, s| s.participants.replace(original.fetch(name)) }
  h.network[missing.downcase].__send__(:attach, rig.sessions.fetch(missing))
  rig.advance(60)
  assert(h.clients.values.all? { |c| c.engine.turn == 1 }, 'same-session rejoin did not receive the pending serve')
  assert(h.network.values.all? { |c| c.instance_variable_get(:@generation) == 0 }, 'brief membership absence restarted the rally')
ensure
  rig.close
end
puts 'PASS relay ordering and rejoin: both team layouts, authenticated future actions, full recipients on same-session return'
