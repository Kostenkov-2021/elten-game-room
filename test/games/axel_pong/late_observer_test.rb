require_relative "../../support/pong_client"

h = PongHarness.new(viewers: %w[Alice Bob], options: {'difficulty' => 6},
  preferences: {'Alice' => {'auto_return' => true}, 'Bob' => {'auto_return' => true}})
begin
  h.advance(40)
  h.press(h.players.fetch(h.clients.fetch('Alice').engine.server))
  10_000.times { h.advance(1); break if h.clients.fetch('Alice').engine.turn >= 8 }
  assert(h.clients.fetch('Alice').engine.turn >= 8, 'Rally did not reach late join')
  h.instance_variable_get(:@viewers) << 'Watcher'
  audio = PongTestAudio.new
  goals = []
  audio.define_singleton_method(:goal) { |**data| goals << data }
  observer = GameRoomPong::Client.new(Program.new, h.rules, clock: -> { h.now }, audio: audio,
    channel_factory: ->(**args) { PongTestChannel.new(h.network, **args) })
  observer.bind_screen(session_id: 300, table_id: 20, owner: 'Alice', viewer: 'Watcher',
    members: -> { h.instance_variable_get(:@viewers) })
  observer.start
  observer.before_wait(h.replay, 'Watcher')
  surface = PongTestSurface.new
  surface.controls['press'] = 0
  observer.attach_view(Form.new([]), surface)
  h.clients['Watcher'], h.surfaces['Watcher'] = observer, surface
  20_000.times { h.advance(1); break if h.clients.fetch('Alice').engine.turn >= 170 }
  h.advance(4)
  host = h.clients.fetch('Alice')
  assert(host.engine.turn >= 170, 'Long rally was not completed')
  assert(h.network.values.all? { |channel| channel.resets.zero? }, 'Late observer caused a reconnect')
  assert(observer.send(:rally_state).deferred_events.empty?, 'Spectator retained unplayable actions')
  assert(observer.instance_variable_get(:@observer_turn) == host.engine.turn && observer.engine.turn.zero?, 'Spectator did not use snapshot-only physics')
  assert(audio.updates.last[0]['fx'].any?, 'Snapshot sound effects were lost')
  assert(!observer.request_hurry && observer.context_data['pong_point'] == nil, 'Spectator gained control')
  h.programs.each_value { |program| program.instance_variable_set(:@pong_preferences, {'auto_return' => false}) }
  5_000.times { h.advance(1); break if host.context_data['pong_point'] }
  h.advance(4)
  value = host.context_data['pong_point']
  assert(value && goals.length == 1, 'Late observer missed or duplicated the point sound')
  h.accept_point(value)
  h.advance(400)
  assert(observer.instance_variable_get(:@observer_turn).zero?, 'New rally kept the old spectator turn')
  opponent = h.players[1 - host.engine.server]
  $spoken_messages.clear
  assert(h.clients.fetch(opponent).request_hurry, 'Cannot hurry the next server')
  h.advance(8)
  assert($spoken_messages.length == 3, 'Spectator did not receive the new rally warning exactly once')
  assert(h.network.values.all? { |channel| channel.resets.zero? }, 'Point/rematch created an observer reconnect')
ensure
  h.close
end
puts 'PASS late observer: 170+ turns, snapshot audio, no backlog/reconnect/control, point and next-rally hurry'
