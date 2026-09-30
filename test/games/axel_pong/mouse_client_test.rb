require_relative "../../support/pong_client"
require_relative "../../support/axel_pong_mouse"

def attach_mouse(harness, viewer)
  backend = PongMouseBackend.new
  mouse = GameRoomPong::MouseControl.new(backend: backend)
  client = harness.clients.fetch(viewer)
  client.instance_variable_set(:@mouse, mouse)
  surface = harness.surfaces.fetch(viewer)
  surface.define_singleton_method(:input_active?) { |_form| @mouse_active != false }
  [client, surface, mouse, backend]
end

[
  [%w[Alice Bob], 'Alice'], [%w[Alice Bob], 'Bob'],
  [%w[Bob Carol], 'Carol'],
  [['Alice', 'bot:7:1'], 'Alice'], [['Bob', 'bot:7:1'], 'Bob']
].each do |players, name|
  h = PongHarness.new(players: players)
  begin
    h.advance(220)
    client, surface, mouse, backend = attach_mouse(h, name)

    h.advance(4)
    side = players.index(name)
    backend.delta = [1000, 0]
    h.advance(16)
    backend.delta = [0, 0]
    h.advance(8)
    assert(h.clients['Alice'].engine.paddles[side] == 19, "#{players}/#{name}: wrong mouse position")
    assert(h.clients['Alice'].engine.ball['dy'].zero?, 'mouse movement served ball')
    if client.engine
      assert(client.engine.paddles[side] == 19, 'local/owner paddle mismatch')
    end
    # Turning a control into chat blocks both mouse polling and movement.
    surface.instance_variable_set(:@mouse_active, false)
    backend.delta = [-100, 0]
    count = backend.samples
    h.advance(8)
    assert(backend.samples == count, 'chat polled mouse')
    assert(h.clients['Alice'].engine.paddles[side] == 19, 'chat moved paddle')
    backend.delta = [0, 0]
    surface.instance_variable_set(:@mouse_active, true)
    h.advance(4)
    backend.delta = [-5, 0]
    h.advance(1)
    backend.delta = [0, 0]
    h.advance(8)
    assert(h.clients['Alice'].engine.paddles[side] == 18, 'return from chat / brief guest motion lost')
    # Detaching stops reads; reattaching automatically restores mouse input.
    client.detach_view
    assert(!mouse.active?, 'detach failed to suspend input')
    client.attach_view(Form.new([]), surface)
    backend.delta = [0, 0]
    h.advance(8)
    assert(h.clients['Alice'].engine.paddles[side] == 18, 'reattach jumped')
    before = backend.suspends
    h.now += 1
    client.frame
    assert(backend.suspends > before, 'long modal gap did not reset mouse')

    assert(!mouse.respond_to?(:toggle), 'obsolete user switch')
    # Current peer packets transmit position, never raw key/mouse input.
    good = {'turn' => 0, 'goal' => nil, 'x' => 18, 'edges' => 0}
    assert(client.send(:valid_peer_position?, good), 'valid mouse position rejected')
    [nil, '18', 0, 30, Float::INFINITY, Float::NAN].each do |bad|
      assert(!client.send(:valid_peer_position?, good.merge('x' => bad)), 'invalid position accepted')
    end
  ensure
    h.close
  end
end

h = PongHarness.new
begin
  client, surface, mouse, backend = attach_mouse(h, 'Watcher')

  h.advance(50)
  assert(!mouse.active? && backend.samples.zero?, 'observer controls a paddle')
ensure
  h.close
end
puts 'PASS Pong mouse clients: host/guest, observing owner, local/remote bot, chat, attach/detach, modal gap, packet validation, no unintended serve'

# Real sampling-to-channel paths, not just MouseControl's return values.
[%w[Alice Bob], %w[Bob Carol], ['Alice', 'bot:7:1'], ['Bob', 'bot:7:1']].each do |players|
  h = PongHarness.new(players: players)
  begin
    h.advance(220)
    server = players[h.clients['Alice'].engine.server]
    next if GameRoomParticipants.bot?(server)
    client, surface, mouse, backend = attach_mouse(h, server)

    backend.delta = [0, 0, false]
    h.advance(3)
    backend.delta = [0, 0, true]
    h.advance(1)
    backend.delta = [0, 0, false]
    h.advance(8)
    assert(h.clients['Alice'].engine.ball['dy'] != 0, "#{players}: left click lost before channel publication")
    assert(mouse.clicks == 1, 'one click registered multiple presses')
    h.accept_point('0:0')
    backend.delta = [0, 0, true]
    h.advance(370)
    assert(h.clients['Alice'].engine.ball['dy'] == 0, "#{players}: held left button crossed point pause into serve")
    backend.delta = [0, 0, false]
    h.advance(3)
    backend.delta = [0, 0, true]
    h.advance(8)
    assert(h.clients['Alice'].engine.ball['dy'] != 0, "#{players}: release/reclick after point cannot serve")
  ensure
    h.close
  end
end
puts 'PASS mouse clicks through clients: host/guest, observing owner, local/remote bot, brief click and held button across point pause'
