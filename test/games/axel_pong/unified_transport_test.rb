require_relative "../../support/pong_relay"

# Delay the human -> owner leg, not the other guests. Their return must reach
# the other human directly through the real EventChannel, without an owner
# echo or waiting for the owner's copy of that action.
rig = PongRelayFixture.new(players: ['Alice', 'Bob', 'Carol', 'bot:7:1'], rpc_delay: 0.016)
begin
  rig.ready
  h, host = rig.h, rig.h.clients['Alice']
  h.press(h.players[host.engine.server])
  rig.advance(12)
  receiver = host.engine.rotation.hitter(1)
  name = h.players[receiver]
  assert(!GameRoomParticipants.bot?(name) && name != 'Alice', 'fixture must use a remote human receiver')
  other = (h.players.reject { |p| GameRoomParticipants.bot?(p) } - ['Alice', name]).first
  rig.one_way = ->(from, to, packet) { from == name && to == 'Alice' && packet.dig('d', 'action') == 'hit' ? 0.35 : 0.016 }
  actor = h.clients[name]
  actor.engine.ball.merge!('x' => actor.engine.paddles[receiver],
    'y' => actor.engine.rotation.team(receiver).zero? ? 3.0 : 17.0)
  h.press(name)
  rig.advance(8)
  assert(actor.engine.turn == 2 && h.clients[other].engine.turn == 2 && host.engine.turn == 1,
    'mixed human return still waited for the owner')
  events = rig.transmissions.select { |t| t[:packet].dig('d', 'action') == 'hit' }
  assert(events.length == 1 && events.first[:sender] == name && events.first[:targets].sort == (h.clients.keys - [name]).sort,
    'human return was echoed or did not directly address all humans')
  rig.advance(50)
  assert(h.clients.values.all? { |c| c.engine.turn == 2 && c.engine.goal == nil }, 'delayed owner did not catch up')
ensure
  rig.close
end

# Bot actions share the owner's reliable sequence with its human actions,
# while authenticity is checked per seat. No bot has a network account.
rig = PongRelayFixture.new(players: ['Bob', 'bot:7:1', 'Carol', 'bot:7:2'], rpc_delay: 0.016)
begin
  rig.ready
  h, host = rig.h, rig.h.clients['Alice']
  h.press(h.players[host.engine.server])
  rig.advance(12)
  seat = host.engine.rotation.hitter(1)
  actor = h.clients[h.players[seat]]
  actor.engine.ball.merge!('x' => actor.engine.paddles[seat], 'y' => 17.0)
  h.press(h.players[seat])
  rig.advance(12)
  bot = host.engine.rotation.hitter(2)
  assert(GameRoomParticipants.bot?(h.players[bot]), 'fixture expected a bot return')
  forged = {'action' => 'hit', 'side' => bot, 'turn' => 3, 'r' => 0,
    'ball' => host.engine.ball.merge('dy' => 1)}
  target = h.clients['Carol']
  assert(!target.send(:peer_event_sender?, 'Bob', forged), 'human may claim bot ownership')
  assert(!target.send(:peer_event_sender?, 'Watcher', forged), 'observer may claim bot ownership')
  assert(!target.send(:peer_event_sender?, 'Alice', forged.merge('side' => 0)), 'owner may impersonate another human')
  assert(!host.send(:peer_event_sender?, 'Alice', forged), 'owner accepted an echo of its owned action')
  assert(target.send(:peer_event_sender?, 'Alice', forged), 'owner may not act for its bot')
  assert(!target.send(:valid_peer_event?, forged.merge('side' => 3)), 'wrong bot may take its teammate turn')
  host.engine.ball.merge!('x' => host.engine.paddles[bot], 'y' => -0.01)
  rig.advance(12)
  assert(h.clients.values.all? { |c| c.engine.turn == 3 }, 'delegated bot return was not shared')
  emitted = rig.transmissions.select { |t| t[:packet].dig('d', 'action') == 'hit' && t[:packet].dig('d', 'side') == bot }
  assert(emitted.length == 1 && emitted.first[:sender] == 'Alice', 'bot had multiple controllers')
  assert(rig.sessions.keys.none? { |name| GameRoomParticipants.bot?(name) }, 'fixture created a bot network account')
ensure
  rig.close
end

# A local bot game may begin before Communications exists. The first eventual
# connection must not erase an in-progress local flight or require observers.
h = PongHarness.new(players: ['Alice', 'bot:7:1'], viewers: ['Alice'])
begin
  channel, client = h.network['alice'], h.clients['Alice']
  channel.epoch, channel.connected = nil, false
  h.advance(5)
  assert(!client.paused && client.engine.turn.zero?, 'local bots waited for network setup')
  h.press('Alice')
  h.advance(8)
  original = client.engine
  assert(original.turn == 1, 'local serve failed without network')
  channel.epoch, channel.connected = 'first-connection', true
  h.advance(1)
  assert(client.engine.equal?(original) && client.engine.turn == 1 && !client.paused, 'network setup restarted local game')
ensure
  h.close
end

# A mixed invitation must not be accepted by the old central-input dialect.
require_relative "../../support/realtime_event_channel"
now = 0.0
work = ChannelWork.new
program = ChannelProgram.new('Bob')
channel = GameRoomRealtime::EventChannel.new(program: program, match: 'mixed', owner: 'Alice', viewer: 'Bob',
  clock: -> { now }, members: -> { %w[Alice Bob] }, work: work, event_work: ChannelWork.new)
channel.enable_events('pong-doubles-mixed-peer-1', routing: :peers)
channel.tick; work.finish; channel.tick
endpoint = program.endpoints.first
session = ChannelSession.new('mixed-session', 'Bob', %w[Alice Bob])
old = ChannelInvitation.new(session, metadata: {'gr_realtime' => 1, 'match' => 'mixed', 'events' => 'pong-doubles-1'})
endpoint.deliver(old); channel.tick
assert(old.accepts.zero? && !work.operation, 'mixed client accepted incompatible central-input protocol')
channel.close
puts 'PASS unified transport: direct human return before delayed owner, delegated bot authorization, no bot accounts, offline local start and dialect separation'
