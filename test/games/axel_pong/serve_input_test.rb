require_relative "../../support/pong_client"

rules = GameRoomGames::AxelPong.new
repository = Object.new
def repository.players_for(session); session['__players']; end
def repository.actor_of(event, _session); event['actor']; end
def repository.event_id(event); event['__id']; end

['Alice', 'Bob'].each do |server|
  [false, true].each do |held|
    now = 0.0
    network, clients, surfaces = {}, {}, {}
    session = {'__players' => %w[Alice Bob], 'player_one' => 'Alice',
      'options' => JSON.generate(rules.default_options)}
    first = Digest::SHA256.hexdigest('GameRoom:axel_pong:50:501')[0, 24][-1].to_i(16) % 2
    points = ((%w[Alice Bob].index(server) - first) % 2) * 2 + 1
    events = points.times.map do |i|
      {'__id' => i + 1, 'actor' => 'Alice', 'action' => 'pong_point', 'value' => "#{i}:0"}
    end
    replay = rules.replay(session, events, repository)
    %w[Alice Bob].each do |name|
      client = GameRoomPong::Client.new(Program.new, rules, clock: -> { now }, audio: PongTestAudio.new,
        channel_factory: ->(**args) { PongTestChannel.new(network, **args) })
      client.bind_screen(session_id: 501, table_id: 50, owner: 'Alice', viewer: name, members: -> { %w[Alice Bob] })
      client.start
      client.before_wait(replay, name)
      surfaces[name] = PongTestSurface.new
      surfaces[name].controls = {'move' => 0, 'hit' => false, 'press' => 0}
      client.attach_view(Form.new([]), surfaces[name])
      clients[name] = client
    end
    step = ->(count) { count.times { now += 0.016; clients.each_value(&:frame) } }
    step.call(30)
    assert(clients.values.all?(&:paused), 'not in the between-point pause')
    3.times do |index|
      surfaces[server].controls = {'move' => 0, 'hit' => true, 'press' => index + 1}
      step.call(2)
      surfaces[server].controls['hit'] = false unless held
      step.call(2)
    end
    step.call(380)
    host = clients['Alice']
    assert(clients.values.none?(&:paused), 'next rally did not become ready')
    assert(host.engine.ball['dy'] == 0 && host.engine.goal == nil,
      "#{server}: buffered #{held ? 'held' : 'released'} presses served after the point")
    if held
      # An OS key-repeat event while still holding Up is not a new deliberate
      # serve after the pause; release is required first.
      surfaces[server].controls['press'] += 1
      step.call(8)
      assert(host.engine.ball['dy'] == 0, "#{server}: key repeat across pause served")
    end
    surfaces[server].controls['hit'] = false
    step.call(5)
    surfaces[server].controls['press'] += 1
    # A genuine quick tap can be released before the frame/network samples it.
    step.call(8)
    expected_direction = server == 'Alice' ? 1 : -1
    assert(host.engine.ball['dy'] == expected_direction, "#{server}: fresh released tap was lost")
    clients.each_value(&:close)
  end
end

# Holding during active play is deliberately supported by the original.
# Preserve last-moment defence without turning it into an early auto-return.
[0, 1].each do |side|
  game = GameRoomPong::Engine.new(rally: side * 2)
  held_input = {'move' => 0, 'hit' => true, 'press' => 0}
  inputs = [{}, {}]
  inputs[side] = held_input
  game.step(inputs)
  assert(game.ball['dy'].zero?, 'hold without a fresh press served the ball')
  incoming = side.zero? ? -1 : 1
  game.ball.merge!('x' => 15.0, 'y' => side.zero? ? 4.0 : 16.0, 'dy' => incoming, 'speed' => 0.1)
  game.step(inputs)
  assert(game.ball['dy'] == incoming, 'hold became an early automatic return')
  game.ball['y'] = side.zero? ? 0.5 : 19.5
  game.step(inputs)
  assert(game.ball['dy'] == -incoming, 'original held-key goal defence was removed')
  game.ball.merge!('x' => 15.0, 'y' => side.zero? ? 4.0 : 16.0, 'dy' => incoming)
  held_input['press'] = 1
  game.step(inputs)
  assert(game.ball['dy'] == -incoming, 'a fresh press could no longer return early')
end
puts 'PASS Pong serve input: host/guest, paused taps, hold/repeat across readiness, fresh quick taps and original held-key goal defence'
