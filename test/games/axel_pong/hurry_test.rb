require_relative "../../support/pong_client"

[%w[Alice Bob], %w[Bob Carol]].each do |players|
  match = PongHarness.new(players: players)
  match.advance(220)
  host = match.clients['Alice']
  server = players[host.engine.server]
  opponent = players[1 - host.engine.server]
  caller = match.clients[opponent]
  assert(!match.clients[server].request_hurry, 'server hurried themselves')
  assert(!match.clients['Watcher'].request_hurry, 'spectator hurried a player')
  $spoken_messages.clear
  assert(caller.request_hurry, 'legal warning rejected')
  match.advance(8)
  assert($spoken_messages.length == match.clients.length, 'missing or duplicate warning')
  deadline = host.instance_variable_get(:@hurry_until)
  caller.request_hurry
  match.advance(8)
  assert(host.instance_variable_get(:@hurry_until) == deadline, 'repeat extended warning')
  match.advance(590)
  assert(host.context_data['pong_point'] == nil, 'penalty before ten seconds')
  match.advance(35)
  expected = "0:#{1 - host.engine.server}:timeout"
  assert(host.context_data['pong_point'] == expected, 'missing acknowledged timeout point')
  match.accept_point(expected)
  assert(match.replay.state[:scores].sum == 1 && match.replay.history.any? { |h| h.key.to_s.start_with?('timeout:') },
    'timeout not durable or history missing')
  match.advance(380)
  assert(host.engine.ball['dy'].zero? && host.context_data['pong_point'] == nil, 'timeout replayed in new rally')
  match.close
end

[:serve, :outage].each do |kind|
  match = PongHarness.new
  match.advance(220)
  host = match.clients['Alice']
  server = match.players[host.engine.server]
  match.clients[match.players[1 - host.engine.server]].request_hurry
  match.advance(10)
  if kind == :serve
    match.press(server)
    match.advance(8)
    assert(host.instance_variable_get(:@hurry_until) == nil, 'valid serve did not cancel warning')
  else
    match.network.each_value { |channel| channel.drop = true }
    match.advance(700)
    assert(host.context_data['pong_point'] == nil && host.instance_variable_get(:@hurry_until) == nil,
      'network outage became a serve penalty')
  end
  match.close
end

# The guest serves locally just before the owner's timeout, but that reliable
# serve arrives after it. Both must accept the same authoritative point.
match = PongHarness.new
match.clients.each_value { |client| client.define_singleton_method(:first_server) { 1 } }
match.clients.each_value { |client| client.send(:reset_rally) }
match.advance(220)
host = match.clients['Alice']
assert(host.request_hurry, 'timeout race warning')
match.advance(620)
match.network['bob'].hold_events = true
match.press('Bob')
match.advance(3)
assert(match.clients['Bob'].engine.turn == 1 && match.clients['Bob'].engine.goal == nil, 'late local serve missing')
match.advance(12)
match.network['bob'].release_events
match.advance(10)
assert(host.context_data['pong_point'] == '0:0:timeout' &&
  match.players.all? { |p| match.clients[p].engine.goal == 0 }, 'serve/timeout race left divergent clients')
match.close
puts 'PASS Pong hurry: both server roles, observer owner, 10 seconds, cooldown, no observer/self penalty, cancellation and durable replay'
