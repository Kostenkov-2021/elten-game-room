require_relative "../../support/pong_client"

h = PongHarness.new
begin
  h.advance(220)
  host = h.clients['Alice']
  guest = h.clients['Bob']
  guest.send(:connection_state).public_send(:next_send=, h.now + 0.039)
  guest.send(:rally_state).public_send(:snapshot=, guest.engine.snapshot.merge('goal' => 0))
  sent = h.network['bob'].sent.length
  guest.send(:send_peer_state, h.now)
  assert(h.network['bob'].sent.length == sent + 1, 'known goal waited for periodic paddle status')
  packet = JSON.parse(h.network['bob'].sent.last)
  assert(packet.dig('d', 'goal') == 0, 'goal status did not carry the locally observed result')
  10.times { guest.send(:send_peer_state, h.now) }
  assert(h.network['bob'].sent.length == sent + 1, 'immediate status flooded the relay on every frame')
  guest.send(:send_peer_state, h.now + 0.041)
  assert(h.network['bob'].sent.length == sent + 2, 'periodic resend was disabled after goal status')
  assert(!host.send(:point_state).pending_point, 'a status alone awarded a goal without engine/peer agreement')
  guest.send(:connection_state).public_send(:epoch=, 'replacement')
  guest.send(:send_peer_state, h.now + 0.041)
  assert(h.network['bob'].sent.length == sent + 3, 'replacement connection inherited a stale goal-send marker')
  guest.send(:rally_state).public_send(:snapshot=, guest.engine.snapshot.merge('goal' => nil))
  guest.send(:send_peer_state, h.now + 0.042)
  assert(h.network['bob'].sent.length == sent + 3, 'normal paddle state bypassed periodic rate limit')
ensure
  h.close
end
puts 'PASS goal status: immediate once, periodic retry retained, no premature point'
