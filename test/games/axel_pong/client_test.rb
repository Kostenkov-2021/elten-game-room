require_relative "../../support/pong_client"

# Two independent simulations, replacing the old remote-key/snapshot model.
# Native sender/epoch guards have their own test, not mocked here.
[%w[Alice Bob], %w[Bob Carol]].each do |players|
  h = PongHarness.new(players: players)
  h.advance(220)
  assert(h.clients.values.none?(&:paused), 'handshake never resumed')
  host = h.clients['Alice']
  server = players[host.engine.server]
  receiver = players[1 - host.engine.server]
  h.press(server, move: 1)
  h.advance(8)
  assert(h.clients[server].engine.ball['dy'] != 0, 'local serve missing')
  assert(h.clients[server].engine.paddles[host.engine.server] > 15, 'shared X input reversed')
  assert(h.clients[receiver].engine.ball['dy'] != 0, 'serve event not delivered')
  assert(h.clients[receiver].engine.turn == 1, 'serve lost or duplicated')
  h.surfaces[server].controls['move'] = 0

  h.network.each_value { |c| c.drop = true }
  before = h.clients[receiver].engine.tick
  h.advance(60)
  assert(h.clients.values.none?(&:paused), 'position packet age froze a live match')
  assert(h.clients[receiver].engine.tick > before, 'local flight did not advance')
  local = h.clients[receiver].engine
  side = players.index(receiver)
  local.ball.merge!('x' => local.paddles[side], 'y' => side.zero? ? 4.0 : 16.0)
  h.press(receiver)
  h.advance(4)
  assert(h.clients[server].engine.turn == 2, 'reliable return depended on position snapshots')
  h.network.each_value { |c| c.drop = false }
  h.advance(6)

  # Only the receiving player concedes, not the host's outbound simulation.
  side = players.index(server)
  loser = h.clients[server].engine
  loser.ball.merge!('x' => 1.0, 'y' => side.zero? ? 0.5 : 19.5)
  h.network[server.downcase].hold_events = true
  h.advance(5)
  if server != 'Alice'
    assert(host.context_data['pong_point'] == nil, 'host invented a remote miss')
  end
  h.network[server.downcase].release_events
  h.advance(10)
  value = "0:#{1 - side}"
  assert(host.context_data['pong_point'] == value, 'conceded point did not pass player acknowledgements')
  context = GameRoomGames::ActionContext.new(table_owner: 'Alice', local_data: host.context_data)
  selection = {'kind' => 'command', 'action' => 'pong_point', 'point' => value}
  assert(h.rules.action_for(selection, h.replay, 'Alice', context: context).first == :ok, 'normal durable action failed')
  assert(h.rules.action_for(selection, h.replay, receiver, context: nil).first == :invalid, 'external score accepted')
  positions = host.engine.paddles.dup
  h.accept_point(value)
  h.advance(380)
  assert(host.engine.paddles == positions, 'paddles reset after the point')
  assert(host.context_data['pong_point'] == nil && host.engine.ball['dy'].zero?, 'point/serve repeated into next rally')

  before = host.engine.tick
  h.now += 0.4
  h.clients.each_value(&:frame)
  assert(host.engine.tick - before <= 1 && !host.paused, 'short scheduler stall paused or fast-forwarded')
  h.network.each_value { |c| c.drop = true }
  h.advance(350)
  assert(h.clients.values.all?(&:paused), 'real stopped stream not detected')
  h.network.each_value { |c| c.drop = false; c.epoch = 'replacement' }
  h.advance(380)
  assert(host.engine.ball['dy'] == 0 && h.replay.state[:rally] == 1, 'reconnect changed score or resumed stale flight')
  h.close
  assert(h.network.values.none?(&:connected?), 'channel leaked')
end
puts 'PASS original local Pong: two humans, owner-observer, reliable returns/misses, position loss, durable score, lifecycle'
