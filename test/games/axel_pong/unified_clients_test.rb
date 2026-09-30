require_relative "../../support/pong_client"

def human_pong_players(players)
  players.reject { |name| GameRoomParticipants.bot?(name) }
end

def controlled_pong_client(h, seat)
  name = h.players.fetch(seat)
  h.clients.fetch(GameRoomParticipants.bot?(name) ? 'Alice' : name)
end

def ready_unified_pong(h)
  750.times do
    break if h.clients.values.none?(&:paused)
    h.advance(1)
  end
  assert(h.clients.values.none?(&:paused), 'unified match did not become ready')
end

# Every human keeps their own engine even when the owner also controls bots.
[
  ['Alice', 'bot:7:1'], ['Bob', 'bot:7:1'],
  ['Alice', 'Bob', 'Carol', 'bot:7:1'],
  ['Bob', 'Carol', 'Dave', 'bot:7:1'],
  ['Alice', 'bot:7:1', 'Bob', 'bot:7:2'],
  ['bot:7:1', 'Bob', 'bot:7:2', 'bot:7:3']
].each do |players|
  viewers = (['Alice'] + human_pong_players(players) + ['Watcher']).uniq
  options = players.length == 4 ? {'team_size' => 2, 'team_seats' => [0, 0, 1, 1]} : {}
  h = PongHarness.new(players: players, viewers: viewers, options: options)
  begin
    assert(h.clients.values.all? { |c| c.is_a?(GameRoomPong::PeerPlay) && c.engine.is_a?(GameRoomPong::PeerEngine) },
      'a bot still switches humans to owner-side simulation')
    ready_unified_pong(h)
    host = h.clients['Alice']
    16.times do |rally|
      ready_unified_pong(h)
      rotation = host.engine.rotation
      server = players[rotation.server]
      h.press(server) unless GameRoomParticipants.bot?(server)
      450.times do
        break if host.engine.turn > 0
        h.advance(1)
      end
      h.advance(8)
      assert(h.clients.values.all? { |c| pong_presented_turn(c) == 1 }, "#{players} rally #{rally}: serve not shared")
      4.times do |index|
        turn = index + 1
        seat = rotation.hitter(turn)
        actor = controlled_pong_client(h, seat)
        bot = GameRoomParticipants.bot?(players[seat])
        distance = bot ? -0.01 : 3.0
        actor.engine.ball.merge!('x' => actor.engine.paddles[seat],
          'y' => rotation.team(seat).zero? ? distance : 20.0 - distance)
        h.press(players[seat]) unless bot
        h.advance(8)
        assert(h.clients.values.all? { |c| pong_presented_turn(c) == turn + 1 && pong_presented_goal(c) == nil },
          "#{players} rally #{rally}: seat #{seat} failed its return")
      end
      seat = rotation.hitter(host.engine.turn)
      actor = controlled_pong_client(h, seat)
      actor.engine.ball.merge!('x' => actor.engine.paddles[seat] < 15 ? 29.0 : 1.0,
        'y' => rotation.team(seat).zero? ? -0.01 : 20.01)
      h.advance(12)
      point = "#{rally}:#{1 - rotation.team(seat)}"
      assert(host.context_data['pong_point'] == point, 'agreed mixed point did not reach durable scheduler')
      assert(h.clients.values.all? { |c| pong_presented_goal(c) == host.engine.goal }, 'human/bot goal differs across clients')
      assert(h.clients.reject { |name, _| name == 'Alice' }.values.all? { |c| c.context_data['pong_point'] == nil },
        'guest acquired durable score authority')
      h.accept_point(point)
    end
    h.network.each do |name, channel|
      channel.event_sent.each do |encoded|
        event = JSON.parse(encoded)['d']
        next unless %w[serve hit shield_hit goal].include?(event['action'])
        player = players[event['side']]
        controller = GameRoomParticipants.bot?(player) ? 'Alice' : player
        assert(controller.downcase == name, 'owner relayed a human action or guest controlled a bot')
      end
    end
  ensure
    h.close
  end
end
puts 'PASS unified clients: Single, mixed Doubles, player/observer owner, 16 service rotations, owned actions and durable scoring'
