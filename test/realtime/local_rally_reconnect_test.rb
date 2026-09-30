require_relative '../support/audio_ball_relay'

# Exercise the real EventChannel and both engines, including the cached native
# endpoint contract. Reopening transport for spectators must not restart a
# rally for which this computer owns every playing seat.
[
  [['Alice', 'bot:7:1'], {}],
  [['Alice', 'bot:7:1', 'bot:7:2', 'bot:7:3'], {'team_size' => 2}]
].each do |players, options|
  h = PongHarness.new(players: players, viewers: ['Alice'], options: options)
  begin
    rig = RelayFixture.new
    client = h.clients.fetch('Alice')
    program = h.programs.fetch('Alice')
    program.define_singleton_method(:communication) do
      @test_endpoint = nil if @test_endpoint&.closed?
      @test_endpoint ||= rig.endpoint('Alice')
    end
    program.define_singleton_method(:release) { |_resource| }
    h.network.fetch('alice').close
    channel = GameRoomRealtime::EventChannel.new(program: program,
      match: client.instance_variable_get(:@match), owner: 'Alice', viewer: 'Alice',
      clock: -> { h.now }, members: -> { ['Alice', 'Watcher'] },
      work_factory: -> { rig.worker('Alice') }, event_work_factory: -> { rig.worker('Alice') })
    h.network['alice'] = channel
    client.instance_variable_set(:@channel, channel)
    client.before_wait(h.replay, 'Alice')
    advance = ->(count) do
      count.times do
        h.now += 0.016
        rig.now = h.now
        rig.advance_work
        client.frame
      end
    end
    advance.call(20)
    assert(channel.connected? && !client.paused, 'local Pong was not ready')
    h.press('Alice')
    advance.call(2)
    old_engine, old_epoch = client.engine, channel.epoch
    assert(old_engine.turn == 1 && old_engine.goal.nil?, 'local Pong did not serve')
    rig.endpoints.fetch('Alice').close
    advance.call(5)
    assert(channel.connected? && channel.epoch != old_epoch, 'Pong endpoint did not reconnect')
    assert(client.engine.equal?(old_engine) && client.engine.turn == 1 && h.replay.state[:rally].zero?,
      'local Pong rally was restarted or scored by a spectator transport reconnect')
    assert(!client.paused, 'local Pong remained paused after reconnect')
  ensure
    h.close
  end
end

h = AudioBallRelayHarness.new(players: ['Alice', 'bot:7:1'], viewers: ['Alice', 'Watcher'])
begin
  h.wait_ready
  h.advance(20)
  client, channel = h.clients.fetch('Alice'), h.network.fetch('alice')
  h.press('Alice', 'prepare', 'up')
  old_engine, old_epoch = client.engine, channel.epoch
  assert(old_engine.phase == :flying && old_engine.turn == 2, 'local Audio Ball did not hit')
  h.rig.endpoints.fetch('Alice').close
  h.advance(8)
  assert(channel.connected? && channel.epoch != old_epoch, 'Audio Ball endpoint did not reconnect')
  assert(client.engine.equal?(old_engine) && client.engine.phase == :flying && client.engine.turn == 2,
    'local Audio Ball rally was restarted by transport reconnect')
  h.advance(60)
  watcher = h.clients.fetch('Watcher')
  assert(watcher.engine.turn == client.engine.turn && watcher.engine.phase == client.engine.phase,
    'spectator did not recover the preserved rally')
  assert(h.replay.state[:rally].zero?, 'reconnection fabricated a durable point')
ensure
  h.close
end

# Remote playing seats still require the established restart/reconciliation
# boundary. A local host is not sufficient to call the match local.
h = PongHarness.new(viewers: %w[Alice Bob])
begin
  h.advance(30)
  previous = h.clients.fetch('Alice').engine
  h.network.each_value { |channel| channel.epoch = 'new-wire-generation' }
  h.advance(1)
  assert(!h.clients.fetch('Alice').engine.equal?(previous), 'remote Pong incorrectly kept an unagreed engine')
ensure
  h.close
end

puts 'PASS local rally reconnect: Pong single/doubles, Audio Ball and spectator catch-up; remote restart retained'
