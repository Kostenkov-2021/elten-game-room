require_relative "../../support/pong_relay"

rig = PongRelayFixture.new
begin
  rig.ready
  h, host = rig.h, rig.h.clients['Alice']
  h.press(h.players[host.engine.server])
  rig.advance(40)
  # Put the next return in range locally. Then measure dissemination only;
  # do not confuse this with physical travel time or LiveSessions score writes.
  actor = h.players[host.engine.rotation.hitter(host.engine.turn)]
  assert(actor != 'Alice', 'latency fixture needs a non-owner returning player')
  client = h.clients.fetch(actor)
  side = client.instance_variable_get(:@side)
  client.engine.ball.merge!('x' => client.engine.paddles[side],
    'y' => client.engine.rotation.team(side).zero? ? 3.0 : 17.0)
  old_turn = client.engine.turn
  h.press(actor)
  observed = {}
  80.times do
    rig.advance(1)
    h.clients.each { |name, c| observed[name] ||= h.now if c.engine.turn == old_turn + 1 }
  end
  action = rig.transmissions.find { |t| t[:sender] == actor && t[:packet].dig('d', 'action') == 'hit' }
  assert(action, 'return was not transmitted')
  receivers = h.players - [actor]
  measured = receivers.to_h { |name| [name, observed[name] && ((observed[name] - action[:at]) * 1000).round] }
  queue_wait = ((action[:at] - observed.fetch(actor)) * 1000).round
  total = receivers.to_h { |name| [name, observed[name] && ((observed[name] - observed.fetch(actor)) * 1000).round] }
  puts JSON.generate(one_way_ms: 40, rpc_response_ms: 120, actor: actor, return_delivery_ms: measured,
    queue_wait_ms: queue_wait, action_to_receiver_ms: total, recipients: action[:targets])
  assert(queue_wait.zero?, 'idle reliable action waited for a later UI tick in the controlled fixture')
  assert((receivers - action[:targets]).empty?, 'return took an unnecessary application hop through the owner')
  assert(measured.values.all? { |ms| ms && ms <= 65 }, 'peer return waited for the owner or the RPC response')
ensure
  rig.close
end
puts 'PASS direct relay action delivery: all required receivers, one hop, no RPC-response wait at receiver'
