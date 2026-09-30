require_relative "../../support/pong_client"

h = PongHarness.new
begin
  h.advance(220)
  client = h.clients.fetch('Alice')
  channel = h.network.fetch('alice')
  original = client.engine.snapshot
  packet = lambda do |body, sequence|
    JSON.parse(GameRoomRealtime::Protocol.encode(match: channel.match, epoch: channel.epoch,
      sequence: sequence, kind: 'input', body: {'r' => 0, 'local' => 1, 'turn' => 0, 'goal' => nil}.merge(body)))
  end
  [nil, '18', 0, 30].each_with_index do |position, index|
    channel.inbox['bob'] = packet.call({'x' => position, 'edges' => 0}, 1000 + index)
    client.send(:receive_peer_packets, h.now)
    assert(client.engine.snapshot == original, 'invalid position changed the active engine')
  end
  channel.inbox['bob'] = packet.call({'x' => 18, 'edges' => -1}, 1010)
  client.send(:receive_peer_packets, h.now)
  assert(client.engine.snapshot == original, 'invalid border count changed the active engine')

  # Old raw input is not interpreted by this protocol, even when attached to
  # an otherwise valid status packet. A position cannot serve or set options.
  channel.inbox['bob'] = packet.call({'x' => 18, 'edges' => 0, 'move' => 1,
    'hit' => true, 'press' => 999, 'left_press' => 'bad', 'pointer_keys' => [nil],
    'auto_return' => true}, 1020)
  client.send(:receive_peer_packets, h.now)
  assert(client.engine.paddles == [15.0, 18], 'valid peer position did not reach its owned paddle')
  assert(client.engine.ball == original['b'], 'position interpreted legacy input as a serve')
  assert(client.engine.instance_variable_get(:@automatic) == [false, false], 'remote packet changed personal options')
  after = client.engine.snapshot
  channel.inbox['watcher'] = packet.call({'x' => 25, 'edges' => 1}, 1030)
  client.send(:receive_peer_packets, h.now)
  assert(client.engine.snapshot == after, 'observer status changed a paddle')
  assert(!client.respond_to?(:valid_input?, true), 'obsolete raw-input validator returned')
  assert(!GameRoomPong.const_defined?(:PaddleFeedback, false), 'obsolete secondary paddle model loaded')
  assert(!GameRoomPong::Audio.method_defined?(:play_local_movement), 'obsolete local movement audio path returned')
ensure
  h.close
end
puts 'PASS current Pong input: packet validation/authorship, position-only updates, no remote preferences/raw-input execution or secondary paddle model'
