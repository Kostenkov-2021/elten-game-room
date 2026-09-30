require_relative "../../support/pong_client"

h = PongHarness.new(players: %w[Alice Bob Carol Dave], options: {'team_size' => 2, 'team_seats' => [0, 0, 1, 1]})
begin
  h.advance(550)
  host = h.clients['Alice']
  # Authentication happens at every receiver, not just on the owner. A
  # teammate cannot claim the designated defender's return or host powers.
  h.press(h.players[host.engine.server]); h.advance(6)
  defender = host.engine.rotation.hitter(1)
  teammate = (host.engine.rotation.members(host.engine.rotation.team(defender)) - [defender]).first
  victim = h.clients[h.players[(defender + 1) % 4]]
  event = {'action' => 'hit', 'side' => defender, 'turn' => 2, 'r' => 0,
    'ball' => host.engine.ball.merge('dy' => host.engine.rotation.team(defender).zero? ? 1 : -1)}
  queue = h.network[victim.instance_variable_get(:@viewer).downcase].event_inbox
  queue << [h.players[teammate].downcase, {'d' => event}]
  queue << ['watcher', {'d' => event}]
  queue << [h.players[defender].downcase, {'d' => {'action' => 'timeout', 'side' => host.engine.server, 'turn' => 1, 'r' => 0}}]
  victim.send(:receive_peer_events)
  assert(victim.engine.turn == 1 && victim.engine.goal == nil, 'guest accepted a forged actor or owner-only command')

  # Fresh, acknowledged position traffic alone must not conceal a permanently
  # stale action state. Record a truthful stale peer without dropping packets.
  peer = h.players[defender].downcase
  packet = {'n' => 10000, 'a' => 0, 'd' => {'r' => 0, 'turn' => 0, 'goal' => nil}}
  host.send(:connection_state).peers[peer] = GameRoomRealtime::PeerState.new
  host.send(:connection_state).peers[peer].receive(packet, now: h.now, last_sent: 10000)
  host.send(:check_peer_agreement, h.now)
  host.send(:check_peer_agreement, h.now + 0.5)
  assert(h.network['alice'].resets.zero?, 'normal in-flight disagreement caused recovery')
  host.send(:connection_state).peers[peer].receive(packet.merge('n' => 10001, 'a' => 1), now: h.now + 4.0, last_sent: 10000)
  host.send(:check_peer_agreement, h.now + 4.1)
  assert(h.network['alice'].resets == 1, 'fresh but permanently divergent peer never triggered owner recovery')
  host.send(:check_peer_agreement, h.now + 4.2)
  assert(h.network['alice'].resets == 1, 'disagreement caused a reconnect storm')
  host.send(:point_state).public_send(:pending_point=, '0:1')
  host.send(:check_peer_agreement, h.now + 30)
  assert(h.network['alice'].resets == 1, 'recovery discarded an already agreed pending point')
ensure
  h.close
end

# A direct serve can reach another guest before its owner-authorized timeout.
# That timeout may replace only the first serve, never a subsequent return.
(0..3).each do |side|
  engine = GameRoomPong::PeerEngine.new(side: side, authority: false, teams: [0, 0, 1, 1])
  serving = GameRoomPong::PeerEngine.new(side: 0, authority: true, teams: [0, 0, 1, 1])
  serving.strike(0)
  engine.apply_return(serving.take_transition)
  assert(engine.serve_timeout(confirmed: true) && engine.goal == 1, 'direct early serve defeated owner timeout on a receiver')
  assert(!engine.serve_timeout(confirmed: true), 'confirmed timeout awarded twice')
end
puts 'PASS peer recovery: all receivers authenticate actors, bounded disagreement, pending scores preserved, direct-serve timeout race'
