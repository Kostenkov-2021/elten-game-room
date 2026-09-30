require_relative "../../support/audio_ball_relay"

h = AudioBallRelayHarness.new(viewers: %w[Alice Bob])
h.wait_ready
channel = h.network.fetch('bob')
session = channel.instance_variable_get(:@session)
original = session.method(:send_reliable)
fail_once = true
session.define_singleton_method(:send_reliable) do |data, to:|
  if fail_once
    fail_once = false
    raise EltenAPI::Communication::ConnectionError, 'injected one-shot warning delivery failure'
  end
  original.call(data, to: to)
end
old_epoch = channel.epoch
assert(h.surfaces['Bob'].on_audio_ball_command.call('hurry'), 'initial warning was not accepted locally')
same_session_rejoined = false
1800.times do
  h.clients['Bob'].tick
  h.advance
  if channel.connected? && channel.epoch == old_epoch && !channel.instance_variable_get(:@session).equal?(session)
    same_session_rejoined = true
    assert(h.clients['Bob'].paused, 'same-epoch guest resumed before its missing warning was reconciled')
  end
end
assert(!fail_once && same_session_rejoined, 'regression never exercised a failed warning followed by same-session rejoin')
pending = h.clients['Alice'].context_data['audio_ball_point']
state = h.clients.transform_values { |client| {paused: client.paused, turn: client.engine.turn, warning: client.engine.warning, goal: client.engine.goal} }
puts "Warning recovery after failed send: #{state.inspect}; same_epoch=#{channel.epoch == old_epoch}; pending=#{pending.inspect}"
if pending == nil
  assert(h.clients.values.none?(&:paused), 'same-session warning recovery left a client paused forever')
  assert(h.clients.values.all? { |client| client.engine.warning == nil }, 'failed reliable warning survived only on its sender and cannot be retried')
  assert(h.network.values.all? { |peer| peer.epoch == channel.epoch } && channel.epoch != old_epoch,
    'recovery cleared a local warning without an agreed new generation')
  assert(h.surfaces['Bob'].on_audio_ball_command.call('hurry'), 'recovered possession permanently rejects Ctrl+W')
  h.advance(3)
  remaining = h.clients['Alice'].engine.warning
  assert(remaining && remaining > 0, 'repeated warning did not reach its authoritative holder')
  assert(!h.surfaces['Bob'].on_audio_ball_command.call('hurry'), 'duplicate Ctrl+W restarted the recovered countdown')
  h.advance(1350)
  pending = h.clients['Alice'].context_data['audio_ball_point']
end
assert(pending == '0:1:timeout', 'reliable warning neither delivered nor safely reset for retry')
h.commit
assert(h.replay.state[:scores] == [0, 1], 'warning recovery awarded a missing or duplicate point')
h.advance_for(5.8)
assert(h.clients['Alice'].context_data['audio_ball_point'] == nil && h.replay.state[:rally] == 1,
  'recovered warning generated another point after durable confirmation')
h.press('Alice', 'prepare', 'up')
assert(h.clients.values.all? { |client| client.engine.turn == 2 && client.engine.phase == :flying },
  'same-session recovery left subsequent gameplay usable on only one side')
h.close
assert(h.rig.endpoints.values.all?(&:closed?), 'warning recovery leaked an endpoint')
puts 'PASS Audio Ball failed-warning recovery through real EventChannel and same-session guest rejoin'

h = AudioBallRelayHarness.new(players: %w[Bob Carol], owner: 'Alice', viewers: %w[Alice Bob Carol Watcher])
h.wait_ready
h.clients['Alice'].send(:recover, 'test cooldown setup')
h.advance(300)
assert(h.clients.values.none?(&:paused), 'cooldown setup failed to recover all clients')
old_epoch = h.network['bob'].epoch
assert(h.surfaces['Carol'].on_audio_ball_command.call('hurry'), 'cooldown warning was not accepted')
h.advance(4)
assert(h.clients.values.all? { |client| client.engine.warning != nil }, 'cooldown warning did not reach every client')
h.clients['Carol'].send(:recover, 'test same-session participant recovery')
h.advance(300)
assert(h.network['carol'].connected? && h.network.values.all? { |peer| peer.epoch == old_epoch },
  'cooldown regression did not rejoin the unchanged owner session')
assert(h.clients.values.all?(&:paused), 'same-epoch participant recovery let another player or spectator keep playing during cooldown')
turns = h.clients.transform_values { |client| client.engine.turn }
warnings = h.clients.transform_values { |client| client.engine.warning }
h.press('Bob', 'prepare', 'up')
h.advance(100)
assert(h.clients.all? { |name, client| client.engine.turn == turns[name] && client.engine.warning == warnings[name] },
  'unagreed recovery consumed gameplay input or warning time during the pause')
h.advance(1400)
assert(h.network.values.all? { |peer| peer.epoch != old_epoch } && h.clients.values.none?(&:paused),
  'same-epoch participant recovery never requested an owner-authorized reset after cooldown')
assert(h.clients.values.all? { |client| client.engine.turn == 0 && client.engine.warning == nil },
  'owner-authorized recovery left divergent warning or turn state')
assert(h.surfaces['Carol'].on_audio_ball_command.call('hurry'), 'Ctrl+W remained unusable after owner-observer recovery')
h.advance(1350)
assert(h.clients['Alice'].context_data['audio_ball_point'] == '0:1:timeout', 'owner spectator failed to agree the recovered warning timeout')
h.commit
assert(h.replay.state[:scores] == [0, 1], 'owner-observer recovery lost or duplicated the timeout point')
h.close
assert(h.rig.endpoints.values.all?(&:closed?), 'owner-observer recovery leaked an endpoint')
puts 'PASS Audio Ball same-session participant recovery: owner spectator, cooldown, all-copy pause and warning retry'

h = AudioBallRelayHarness.new
h.wait_ready
old_epoch = h.network['alice'].epoch
[['Watcher', true], ['Bob', 'true']].each do |name, resync|
  channel = h.network.fetch(name.downcase)
  packet = GameRoomRealtime::Protocol.encode(match: h.clients[name].instance_variable_get(:@match), epoch: old_epoch,
    sequence: h.clients[name].send(:connection_state).sequence + 1, kind: 'input',
    body: {'r' => 0, 'turn' => 0, 'goal' => nil, 'ready' => false, 'resync' => resync})
  session = channel.instance_variable_get(:@session)
  session.send_unreliable(packet, to: session.participants.select { |member| member.user == 'Alice' })
  h.advance(20)
  assert(h.network.values.all? { |peer| peer.epoch == old_epoch } && h.clients.values.none?(&:paused),
    'spectator or malformed resync heartbeat interrupted the players')
end
assert(h.surfaces['Bob'].on_audio_ball_command.call('hurry'), 'spectator recovery warning setup failed')
h.advance(4)
h.network['watcher'].reconnect(reason: 'test same-session spectator recovery')
h.advance(300)
assert(h.network.values.all? { |peer| peer.epoch == old_epoch } && h.clients.values.none?(&:paused),
  'spectator rejoin reset or stranded an active human match')
assert(h.clients.values.all? { |client| client.engine.warning != nil }, 'spectator recovery cleared a live warning')
h.advance(1050)
assert(h.clients['Alice'].context_data['audio_ball_point'] == '0:1:timeout', 'spectator rejoin restarted or cancelled the active countdown')
h.close
assert(h.rig.endpoints.values.all?(&:closed?), 'spectator recovery leaked an endpoint')
puts 'PASS Audio Ball warning recovery guards: authenticated boolean requests and non-disruptive spectator rejoin'
