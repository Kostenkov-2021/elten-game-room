require_relative '../../support/uno_communications_prototype'

include GameRoomTest::Assertions
Proto = UnoCommunicationsFixture::Proto
Harness = UnoCommunicationsFixture::Harness
cases = GameRoomTest::Cases.new

def expect_error(type)
  begin
    yield
  rescue type => error
    return error
  end
  raise "Expected #{type}"
end

def queue_current(h)
  actor = h.replay.current_player
  selection = h.game.legal_actions(h.replay, actor).first
  [actor, h.queue(actor, selection)]
end

cases.run('unknown delivery retries the same request and seed without another deal') do
  h = Harness.new
  source = UnoCommunicationsFixture::SeedSource.new(43)
  h.endpoints['Alice'].fail_after_publish = true
  context = GameRoomGames::ActionContext.new(now: 100, random_source: source)
  assert(h.command('Alice', 'deal', context: context) == :uncertain, 'Unknown outcome was not retained')
  h.endpoints['Alice'].fail_after_publish = false
  assert(h.clients['Alice'].retry_pending == :pending, 'Retry failed')
  assert(h.relay.requests.map { |entry| entry.drop(1) }.uniq.one?, 'Retry changed ID or seed/deadline')
  h.settle
  h.consistent!
  assert(h.clients['Alice'].cursor == 1 && h.clients['Alice'].events.one?, 'Deal applied twice')
  assert(source.calls == 1 && !h.clients['Alice'].pending?, 'Retry rerolled or stayed blocked')
end

cases.run('out-of-order delivery and a missing middle receipt recover one prefix') do
  h = Harness.new(observers: ['Observer'])
  h.deal
  3.times do
    queue_current(h)
    h.settle(users: h.players)
  end
  endpoint = h.endpoints['Observer']
  assert(endpoint.inbox.length == 3, 'Insufficient delayed messages')
  endpoint.inbox.delete_at(1)
  endpoint.inbox.reverse!
  h.clients['Observer'].tick
  h.consistent!
  assert(h.clients['Observer'].cursor == 4 && !h.clients['Observer'].recovering?, 'Hole remained after recovery')
end

cases.run('disconnection after acceptance recovers the last move and unblocks the sender') do
  h = Harness.new
  h.deal
  actor, status = queue_current(h)
  assert(status == :pending, 'Move missing')
  h.endpoints[actor].available = false
  h.settle(users: h.players - [actor])
  assert(h.clients[actor].tick == :unavailable && h.clients[actor].pending?, 'Lost echo was falsely acknowledged')
  replacement = h.relay.endpoint(h.clients[actor].identity, actor)
  assert(h.clients[actor].reconnect(replacement) == :ready, 'Recovery did not restore the tail')
  h.consistent!
  assert(!h.clients[actor].pending?, 'Recovered accepted move stayed blocked')
end

cases.run('new spectator catches up without a master snapshot or blocking players') do
  h = Harness.new
  h.deal
  4.times { queue_current(h); h.settle }
  h.add('Late spectator')
  assert(h.clients['Late spectator'].cursor.zero?, 'New spectator invented state')
  assert(h.clients['Late spectator'].recover == :ready, 'Spectator could not recover')
  h.consistent!
end

cases.run('failed recovery leaves input blocked instead of guessing the order') do
  h = Harness.new
  h.deal
  actor, = queue_current(h)
  h.endpoints[actor].available = false
  h.relay.accept
  client = h.clients[actor]
  assert(client.tick == :unavailable && client.recover == :unavailable, 'Disconnect was hidden')
  assert(client.submit({ 'kind' => 'command', 'action' => 'draw' }, context: h.context) == :waiting, 'Input continued over an unknown move')
  h.endpoints[actor].available = true
  assert(client.recover == :ready, 'Recovery did not resume')
  h.settle
  h.consistent!
end

cases.run('forged actors, sequence numbers and malformed wire data cannot alter UNO') do
  h = Harness.new(observers: ['Observer'])
  h.deal
  before = h.replay.state
  command = { 'action' => 'draw', 'value' => '0' }
  attempts = [h.packet('Observer', command, actor: h.replay.current_player),
    h.packet('Observer', command, actor: h.players.first, controller: true),
    JSON.generate(JSON.parse(h.packet('Observer', command)).merge('sequence' => 1)),
    '{broken', '[]', JSON.generate('version' => 1)]
  attempts.each_with_index { |data, index| h.endpoints['Observer'].publish("invalid-#{index}", data) }
  h.settle
  h.consistent!
  assert(h.replay.state == before && h.clients['Alice'].events.length == 1, 'Malformed or unauthorised request changed the model')
  assert(h.clients['Alice'].cursor == 1 + attempts.length, 'Rejected records left a hole')
end

cases.run('a stale-round attempt is consumed but cannot play in the new round') do
  h = Harness.new
  h.deal
  actor = h.replay.current_player
  data = h.packet(actor, { 'action' => 'draw', 'value' => '0' }, round: 0)
  before = h.replay.state
  h.endpoints[actor].publish('old-round', data)
  h.settle
  h.consistent!
  assert(h.replay.state == before && h.clients[actor].last_outcome[:status] == :stale_round, 'Old round changed current cards')
end

cases.run('a changed server receipt is fatal and cannot silently reopen input') do
  h = Harness.new
  h.deal
  original = h.relay.history(h.clients['Alice'].identity, 0).last.first
  forged = original.dup
  forged.data = h.packet('Alice', { 'action' => 'draw', 'value' => '0' })
  before = h.replay.state
  h.endpoints['Alice'].push(forged)
  expect_error(Proto::ProtocolError) { h.clients['Alice'].tick }
  assert(h.replay.state == before, 'Conflicting receipt mutated state')
  assert(h.command('Alice', 'draw') == :failed, 'Conflicting receipt did not stop input')
end

cases.run('the own echo must match the queued bytes before it changes the model') do
  h = Harness.new
  h.deal
  actor, = queue_current(h)
  original = h.relay.accept
  endpoint = h.endpoints[actor]
  forged = original.dup
  forged.data = h.packet(actor, { 'action' => 'draw', 'value' => '999' })
  endpoint.inbox.clear
  endpoint.push(forged)
  before = h.clients[actor].replay.state
  expect_error(Proto::ProtocolError) { h.clients[actor].tick }
  assert(h.clients[actor].replay.state == before && h.clients[actor].pending?, 'Changed echo applied or confirmed another action')
end

cases.run('the simulated server deduplicates IDs and rejects changed retries') do
  h = Harness.new
  h.command('Alice', 'deal')
  request = h.relay.requests.first
  h.relay.accept
  endpoint, id, = request
  endpoint.publish(id, '{}')
  expect_error(Proto::ProtocolError) { h.relay.accept }
  h.settle
  h.consistent!
  assert(h.clients['Alice'].cursor == 1, 'Changed retry created another numbered receipt')
end

cases.run('an accidental second sequence for the same attempt cannot duplicate a penalty') do
  h = Harness.new
  h.deal
  before = h.replay
  actor = h.players.find { |player| player != before.current_player }
  card = before.state[:hands][actor].find { |item| !h.game.send(:interceptable?, before.state, item) }
  assert(h.play(actor, card) == :pending, 'Late attempt was not queued')
  original = h.relay.accept
  h.settle
  copy = original.dup
  copy.sequence += 1
  h.endpoints.each_value { |endpoint| endpoint.push(copy) }
  h.clients.each_value(&:tick)
  h.consistent!
  assert(h.replay.state[:scores][actor] == 3, 'Duplicate attempt charged twice')
end

cases.run('a new match or control epoch cannot consume the previous stream') do
  old = Harness.new
  old.deal
  stale = old.relay.history(old.clients['Alice'].identity, 0).last.first
  [Harness.new(match: 8), Harness.new(epoch: 'second')].each do |fresh|
    fresh.endpoints.each_value { |endpoint| endpoint.push(stale) }
    fresh.settle
    assert(fresh.clients.values.all? { |client| client.cursor.zero? }, 'Stale match packet applied')
    fresh.deal
    fresh.consistent!
  end
  expect_error(Proto::ProtocolError) do
    old.clients['Alice'].reconnect(old.relay.endpoint(old.clients['Alice'].identity, 'Bob'))
  end
  old.clients.each_value(&:close)
  old.endpoints.each_value { |endpoint| endpoint.push(stale) }
  old.clients.each_value(&:tick)
  assert(old.command('Alice', 'draw') == :closed, 'Closed client resumed')
end

cases.run('inbox overflow is explicit and does not slow the other players') do
  h = Harness.new(observers: ['Observer'])
  h.deal
  140.times do |index|
    h.endpoints['Observer'].publish("invalid-#{index}", '{}')
    h.relay.accept
    h.players.each { |player| h.clients[player].tick }
  end
  observer = h.clients['Observer']
  assert(observer.tick == :unavailable && observer.recovering?, 'Inbox overflow was silent')
  assert(observer.recover == :ready, 'Overflow recovery did not catch up')
  observer.tick
  h.consistent!
  assert(h.clients['Alice'].cursor == 141, 'Slow observer blocked active clients')
end

cases.run('gap and retention bounds stop safely rather than growing without limit') do
  [Proto::MAX_GAP + 2, Proto::MAX_RECEIPTS + 1].each do |sequence|
    h = Harness.new
    h.endpoints['Alice'].push(Proto::Receipt.new(identity: h.clients['Alice'].identity,
      sequence: sequence, sender: 'Bob', request_id: 'out-of-bounds', data: '{}'))
    expect_error(Proto::CapacityExceeded) { h.clients['Alice'].tick }
    assert(h.clients['Alice'].cursor.zero? && h.clients['Alice'].fault, 'Bound failure mutated state or continued')
  end
end

cases.run('readers cannot mutate another client or the retained prototype model') do
  h = Harness.new
  h.deal
  view = h.replay
  view.state[:hands].clear
  log = h.clients['Alice'].events
  log.first['value'] = 'broken'
  h.consistent!
  assert(h.replay.state[:hands].length == 3, 'Mutable presentation leaked into the model')
end

puts 'PASS local UNO Communications prototype fault cases (no native network or live accounts)'
