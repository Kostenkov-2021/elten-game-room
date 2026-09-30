require_relative "../../support/pong_client"

# A next-rally event can precede the corresponding LiveSessions point. It must
# survive exactly once; spectators cannot occupy the deferred queue as players.
h = PongHarness.new
h.advance(220)
host = h.clients['Alice']
guest = h.clients['Bob']
future = {'action' => 'hurry_request', 'side' => 1, 'turn' => 0, 'r' => 1}
channel = h.network['alice']
128.times { |n| channel.event_inbox << ['watcher', {'n' => n, 'd' => future.dup}] }
host.send(:receive_peer_events)
assert(host.send(:rally_state).deferred_events.empty?, 'observer occupied future-event buffer')
128.times { |n| channel.event_inbox << ['bob', {'n' => n, 'd' => future.dup}] }
host.send(:receive_peer_events)
assert(host.send(:rally_state).deferred_events.length == 128, 'bounded future events lost')
server = h.players[host.engine.server]
actor = h.clients[server]
assert(actor.engine.strike(actor.engine.server), 'initial fixture serve')
event = actor.engine.take_transition.merge('r' => 0)
if server == 'Alice'
  # For the host, the current legal event is Bob's return after this serve.
  assert(guest.engine.apply_return(event), 'fixture incoming serve')
  guest.engine.ball.merge!('x' => 15.0, 'y' => 17.0)
  assert(guest.engine.strike(1), 'fixture current return')
  event = guest.engine.take_transition.merge('r' => 0)
end
channel.event_inbox << ['bob', {'n' => 129, 'd' => event}]
host.send(:receive_peer_events)
assert(host.engine.turn == event['turn'], 'current action truncated behind deferred queue')
channel.event_inbox << ['bob', {'n' => 130, 'd' => future.dup}]
host.send(:receive_peer_events)
assert(channel.resets == 1 && host.send(:rally_state).deferred_events.empty?,
  'future overflow neither bounded nor recovered')
h.close

h = PongHarness.new
h.advance(220)
host = h.clients['Alice']
guest = h.clients['Bob']
next_engine = GameRoomPong::PeerEngine.new(side: 0, authority: true, rally: 1,
  first_server: 0, level: 2)
assert(next_engine.strike(0), 'next-rally fixture serve')
packet = {'n' => 1, 'd' => next_engine.take_transition.merge('r' => 1)}
h.network['bob'].event_inbox << ['alice', packet]
guest.send(:receive_peer_events)
assert(guest.engine.turn.zero?, 'future serve ran before durable point')
# Keep the fixture's server choice independent from the match hash.
guest.define_singleton_method(:first_server) { 0 }
h.accept_point('0:0')
guest.send(:receive_peer_events)
assert(guest.engine.turn == 1 && guest.engine.ball['dy'] == 1,
  'next-rally serve lost when durable point arrived')
events = guest.engine.events.length
guest.send(:receive_peer_events)
assert(guest.engine.turn == 1 && guest.engine.events.length == events, 'deferred serve repeated')
h.network['bob'].event_inbox << ['alice', packet.merge('d' => packet['d'].merge('r' => 0))]
guest.send(:receive_peer_events)
assert(guest.engine.turn == 1, 'old rally event changed current flight')
h.close

# Arcade is rolled by the owner only. A delayed invisibility cue cannot hide
# the ball again after a newer return; a delayed shield renewal is retained.
class PongEffectsRandom
  attr_reader :calls
  def initialize; @calls = 0; end
  def rand(*_args); @calls += 1; 0.01; end
end
h = PongHarness.new(options: {'arcade' => true})
h.advance(220)
host = h.clients['Alice']
random = PongEffectsRandom.new
host.engine.instance_variable_set(:@rng, random)
server = h.players[host.engine.server]
h.press(server)
h.advance(5)
assert(random.calls.zero?, 'Arcade rolled on serve')
receiver = h.players[1 - host.engine.server]
side = h.players.index(receiver)
h.network.each_value { |c| c.drop = true }
8.times do |index|
  actor = h.clients[receiver]
  actor.engine.ball.merge!('x' => actor.engine.paddles[side], 'y' => side.zero? ? 3.0 : 17.0)
  h.press(receiver)
  h.advance(5)
  assert(h.players.all? { |p| h.clients[p].engine.turn == index + 2 }, 'Arcade return diverged')
  assert(h.players.all? { |p| h.clients[p].engine.invisible && h.clients[p].engine.shields[side] > 600 },
    'owner Arcade effects lost without replaceable position packets')
  receiver = h.players[1 - side]
  side = 1 - side
end
assert(h.network['alice'].event_sent.map { |p| JSON.parse(p)['d']['action'] }.count('effects') == 8,
  'effects not emitted exactly once per return')
assert(h.network['bob'].event_sent.none? { |p| JSON.parse(p)['d']['action'] == 'effects' },
  'guest generated Arcade effects')
h.close

engine = GameRoomPong::PeerEngine.new(side: 0, authority: false, arcade: true)
engine.strike(0)
engine.take_transition
ball = engine.ball.dup.merge('dy' => -1)
assert(engine.apply_return('action' => 'hit', 'side' => 1, 'turn' => 2, 'ball' => ball), 'late cue fixture')
assert(engine.apply_effects('action' => 'effects', 'side' => 0, 'turn' => 1,
  'renew' => true, 'invisible' => true), 'late shield cue rejected')
assert(!engine.invisible && engine.shields[0] == 625, 'late invisibility resurrected after a return')
assert(!engine.apply_effects('action' => 'effects', 'side' => 0, 'turn' => 3,
  'renew' => true, 'invisible' => true), 'future cue changed present flight')
puts 'PASS Pong peer events: actor authorization, deferred/current ordering, overflow recovery, durable rally delay, Arcade authority and stale effects'
