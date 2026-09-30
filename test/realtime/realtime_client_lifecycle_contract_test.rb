require_relative "../support/audio_ball_client"

[
  [PongHarness, GameRoomPong::Client, PongTestAudio, %i[@connection_started @connections @deferred]],
  [AudioBallHarness, GameRoomAudioBall::Client, AudioBallTestAudio,
    %i[@connection_started_at @connection_peers @deferred_events @service_match]]
].each do |harness_type, client_type, audio_type, foreign_fields|
  h = harness_type.new
  client = h.clients.fetch('Alice')
  program = client.instance_variable_get(:@program)
  ping = GameRoomPing.for(program)
  original_channel = client.instance_variable_get(:@channel)
  assert(ping.communications_channel.equal?(original_channel), "#{client_type}: start omitted active ping")
  sample = nil
  original_channel.define_singleton_method(:ping_sample) { sample }
  assert(ping.send(:communications_announcement).nil?, 'No sample must not invent a measurement')
  sample = {relay_udp_ms: 17}
  assert(ping.send(:communications_announcement) == 'Communications UDP relay ping: 17 ms.', 'Connected game sample not exposed')
  sample = {relay_udp_ms: nil}
  assert(ping.send(:communications_announcement) == 'Communications UDP relay ping is unavailable.', 'Missing UDP sample not explained')

  initial = {'__table_owner' => 'Alice', '__control_epoch' => 'initial'}
  engine = client.engine
  client.update_table_control(initial)
  assert(client.engine.equal?(engine) && ping.communications_channel.equal?(original_channel), 'Initial metadata recreated live channel/engine')
  control = initial.merge('__control_epoch' => 'replacement', '__table_owner' => 'Watcher')
  client.update_table_control(control.merge('__control_ready' => false))
  assert(client.instance_variable_get(:@channel).equal?(original_channel), 'Unready authority created a new channel')
  client.send(:point_state).public_send(:pending_point=, '999:0')
  client.send(:point_state).public_send(:goal_preview=, {rally: 999, winner: 0, at: 0})
  prior_state = Marshal.dump(h.replay.state)
  client.update_table_control(control)
  channel = client.instance_variable_get(:@channel)
  assert(!original_channel.connected? && channel.match != original_channel.match, 'Replacement did not isolate the old channel')
  assert(ping.communications_channel.equal?(channel), 'Replacement retained obsolete ping endpoint')
  assert(client.send(:point_state).pending_point.nil? && client.send(:point_state).goal_preview.nil?, 'Replacement retained old pending point/preview')
  assert(client.paused && client.instance_variable_get(:@replay).nil?, 'Replacement did not await authoritative replay')
  assert(foreign_fields.none? { |name| client.instance_variable_defined?(name) }, "#{client_type}: reset created another client implementation's fields")
  assert(Marshal.dump(h.replay.state) == prior_state, 'Control reset changed the accepted score/rally')
  client.before_wait(h.replay, 'Alice')
  assert(client.instance_variable_get(:@owner) == 'Watcher' && channel.instance_variable_get(:@routing) == :peers,
    'Observer coordinator changed reliable peer routing')

  # A new match registers on the same program before the old screen closes.
  # Even an obsolete control update must not take its ping registration away.
  game = harness_type == PongHarness ? h.rules : h.game
  replacement = client_type.new(program, game, clock: -> { h.now }, audio: audio_type.new,
    channel_factory: ->(**args) { AudioBallTestChannel.new({}, **args) })
  replacement.bind_screen(session_id: 301, table_id: 20, owner: 'Alice', viewer: 'Alice', members: -> { %w[Alice Bob] })
  replacement.start
  newest_channel = replacement.instance_variable_get(:@channel)
  client.update_table_control(control.merge('__control_epoch' => 'late-old-control'))
  assert(ping.communications_channel.equal?(newest_channel), 'Old active client stole rematch ping registration')
  client.close
  client.update_table_control(control.merge('__control_epoch' => 'after-close'))
  assert(ping.communications_channel.equal?(newest_channel), 'Old close/control cleared rematch registration')
  final_session = h.session.merge('options' => JSON.generate(game.default_options.merge('target' => 7, 'sets_to_win' => 1)))
  events = harness_type == AudioBallHarness ? h.events.dup : []
  action = harness_type == AudioBallHarness ? 'audio_ball_point' : 'pong_point'
  7.times do |rally|
    events << {'__id' => events.length + 1, 'actor' => 'Alice', '__insertion_user' => 'Alice',
      'action' => action, 'value' => "#{rally}:0", 'created_at' => 100 + rally * 10}
  end
  finished = game.replay(final_session, events, h.repository)
  assert(finished.finished?, 'Lifecycle fixture did not produce a real completed replay')
  replacement.before_wait(finished, 'Alice')
  assert(ping.communications_channel.nil? && !newest_channel.connected?, 'Finished match retained the ping endpoint')
  replacement.close
  replacement.close
  assert(ping.communications_channel.nil?, 'Closed current client retained a ping endpoint')
  h.close
end

puts 'PASS realtime client-owned reset and ping lifecycle: start, missing sample, epoch, observer coordinator, rematch and late close'
