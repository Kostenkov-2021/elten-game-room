require_relative "../support/audio_ball_relay"
require_relative "../support/pong_relay"

# Actual clients and EventChannel with simulated native delivery, not a claim
# of direct connectivity or measured latency across two physical networks.
[false, true].each do |enabled|
  h = AudioBallRelayHarness.new(options: {'p2p_enabled' => enabled})
  h.wait_ready
  request = h.rig.groups.first.fetch(:options)
  assert(request.fetch(:p2p, :off) == (enabled ? :full : :off), 'Audio Ball setup ignored table switch')
  assert(request[:p2p_participants_limit] == 8, 'Audio Ball lost default limit') if enabled
  3.times do
    h.wait_ready
    h.win_point('Alice')
    assert(h.clients.values.all? { |client| client.instance_variable_get(:@replay).state == h.replay.state }, 'Audio Ball scores diverged')
  end
  h.close
  assert(h.rig.endpoints.values.all?(&:closed?), 'Audio Ball endpoint leaked')
end

[%w[Alice Bob], %w[Alice Bob Carol Dave], ['Alice', 'Bob', 'Carol', 'bot:7:1']].each do |players|
  rig = PongRelayFixture.new(players: players, teams: players.length == 4 ? [0, 0, 1, 1] : [0, 1],
    options: {'p2p_enabled' => true, 'p2p_participants_limit' => 8})
  h = rig.h
  1000.times do
    rig.advance(1)
    break if h.clients.values.none?(&:paused)
  end
  assert(h.clients.values.none?(&:paused), 'Pong P2P-configured clients did not synchronize')
  server = players[h.clients['Alice'].engine.server]
  h.press(server) unless GameRoomParticipants.bot?(server)
  1200.times do
    rig.advance(1)
    break if h.clients.values.all? { |client| client.engine.turn > 0 }
  end
  assert(h.clients.values.all? { |client| client.engine.turn > 0 }, 'Pong lost first serve')
  h.clients.each_value(&:close)
end
puts 'PASS P2P-configured local games: Audio Ball relay/off and full requests, three points, Pong single/doubles/mixed serve'
