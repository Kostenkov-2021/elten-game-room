require_relative "../../support/audio_ball_relay"

[
  {players: %w[Alice Bob], owner: 'Alice'},
  {players: %w[Bob Carol], owner: 'Alice'},
  {players: ['bot:20:1', 'Bob'], owner: 'Alice', server: 0}
].each do |options|
  h = AudioBallRelayHarness.new(**options)
  begin
    h.wait_ready
    server = h.players[h.replay.state[:server]]
    h.press(server, 'prepare', 'up') unless GameRoomParticipants.bot?(server)
    2_000.times do
      h.advance
      break if h.clients[options[:owner]].context_data['audio_ball_point']
    end
    assert(h.clients[options[:owner]].context_data['audio_ball_point'], 'no agreed goal on the real event lane')
    h.advance_for(0.6)
    assert(h.audios.values.all? { |audio| audio.calls.count { |call| call.first == :goal } == 1 },
      'reliable preview did not reach every player and spectator before the durable write')
    assert(h.replay.state[:scores] == [0, 0], 'preview modified durable scores')
    h.advance_for(4.0)
    assert(h.clients.values.all?(&:paused), 'a preview let gameplay resume without durable confirmation')
    previews = h.clients.transform_values { |client| client.send(:point_state).goal_preview.dup }
    before = h.replay
    h.commit
    h.clients.each { |name, client| client.event(h.events.last, before, h.replay, name, h.repository) }
    h.audios.each do |name, audio|
      points = audio.calls.select { |call| call.first == :point }
      assert(points.length == 1 && points.first[2][:goal_at] == previews[name][:at], 'commit duplicated a point or lost its preview')
      assert(audio.calls.count { |call| call.first == :goal } == 1, 'goal cue duplicated after commit')
    end
    h.advance_for(2.65)
    assert(h.clients.values.all?(&:paused), 'late durable write omitted the score/serve pause')
    h.advance_for(0.25)
    assert(h.clients.values.none?(&:paused), 'late durable write restarted the entire goal pause')
  ensure
    h.close
  end
  assert(h.rig.endpoints.values.all?(&:closed?), 'preview regression leaked a channel')
end
puts 'PASS Audio Ball agreed goals through real EventChannel: human/bot, owner spectator, delayed commit and exactly-once audio'
