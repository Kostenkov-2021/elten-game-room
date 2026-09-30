require_relative "../../support/pong_client"

# LiveSessions may deliver a point before Communications delivers the next
# rally's snapshot. Exercise this order through the actual attached timer,
# for both a player and a spectator. Human physics now runs locally, but an
# old peer packet still cannot make a new rally ready.
rules = GameRoomGames::AxelPong.new
repository = Object.new
def repository.players_for(session); session['__players']; end
def repository.actor_of(event, _session); event['actor']; end
def repository.event_id(event); event['__id']; end

[%w[Alice Bob], %w[Bob Carol]].each do |players|
  now = 0.0
  network, clients, forms = {}, {}, {}
  session = {'__players' => players, '__insertion_user' => 'Alice', 'player_one' => players.first,
    'options' => JSON.generate(rules.default_options)}
  events = []
  replay = rules.replay(session, events, repository)
  viewers = (['Alice'] + players + ['Watcher']).uniq
  viewers.each do |name|
    client = GameRoomPong::Client.new(Program.new, rules, clock: -> { now }, audio: PongTestAudio.new,
      channel_factory: ->(**args) { PongTestChannel.new(network, **args) })
    client.bind_screen(session_id: 404, table_id: 40, owner: 'Alice', viewer: name, members: -> { viewers })
    client.start
    client.before_wait(replay, name)
    form = Form.new([])
    client.attach_view(form, PongTestSurface.new)
    clients[name], forms[name] = client, form
  end
  step = lambda do |names|
    now += 0.016
    names.each { |name| forms.fetch(name).instance_variable_get(:@timers).each(&:update) }
  end
  220.times { step.call(viewers) }
  assert(clients.values.none?(&:paused), 'initial handshake did not complete')
  guests = viewers - ['Alice']

  # Include two points changing the server, and a replay which skips several
  # points while the viewer catches up with the durable session.
  [1, 1, 3].each do |point_count|
    point_count.times do
      id = events.length
      events << {'__id' => id + 1, '__insertion_user' => 'Alice', 'actor' => 'Alice',
        'action' => 'pong_point', 'value' => "#{id}:0"}
    end
    replay = rules.replay(session, events, repository)
    guests.each do |name|
      clients[name].before_wait(replay, name)
      assert(clients[name].snapshot == nil, 'not a remote reset')
    end
    $spoken_messages.clear
    step.call(guests) # Used to raise nil.server in set_paused.
    assert(guests.all? { |name| clients[name].paused && clients[name].snapshot == nil },
      'old fresh peer resumed a rally with no current snapshot')
    assert($spoken_messages.empty?, 'announced a serve before receiving its state')

    # Still-running old host frames cannot release the waiting remote client.
    8.times { step.call(viewers) }
    assert(guests.all? { |name| clients[name].paused && clients[name].snapshot == nil },
      'old-rally packets supplied the new rally state')
    assert($spoken_messages.empty?, 'old-rally packets announced a new serve')

    clients['Alice'].before_wait(replay, 'Alice')
    8.times { step.call(viewers) }
    assert(guests.all? { |name| clients[name].snapshot && clients[name].paused },
      'missing new paused snapshot or ignored the host readiness delay')
    assert($spoken_messages.empty?, 'paused snapshot announced the serve too early')
    380.times { step.call(viewers) }
    assert(clients.values.none?(&:paused), 'current-rally data did not resume play')
    server = (clients['Alice'].send(:first_server) + events.length / 2) % 2
    assert(clients.values.all? { |c| c.snapshot['server'] == server }, 'wrong new server')
    expected = GameRoomContent.utf8(_('%{player} serves.')) % {player: players[server]}
    assert($spoken_messages == [expected] * viewers.length, 'missing, duplicate or incorrect serve announcements')
    assert(clients.values.all? { |c| c.context_data['pong_point'] == nil }, 'replayed a previous goal')
  end
  clients.each_value(&:close)
  assert(forms.values.all? { |form| form.instance_variable_get(:@timers).empty? }, 'timer leaked after reset tests')
end

# Even a direct resume request cannot invent a server without a validated
# snapshot. This also covers the first connection before any data arrives.
client = GameRoomPong::Client.new(Program.new, rules, audio: PongTestAudio.new)
$spoken_messages.clear
client.send(:set_paused, false)
assert(client.paused && $spoken_messages.empty?, 'empty client resumed or announced an invented server')
client.close
puts 'PASS Pong rally synchronization: player/spectator, observer host, point-before-snapshot, stale data, skipped points, server changes and timers'
