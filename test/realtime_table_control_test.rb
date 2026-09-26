require_relative 'support/audio_ball_client'

[
  [PongHarness, %w[Alice Bob], {}],
  [AudioBallHarness, %w[Alice Bob], {}],
  [PongHarness, %w[Alice Bob Carol bot:7:1], {'team_size'=>2, 'team_seats'=>[0,0,1,1]}]
].product([false, true]).each do |(type, original_players, original_options), p2p|
  players = original_players.dup
  options = original_options.merge('p2p_enabled' => p2p, 'p2p_participants_limit' => 12)
  original_bots = players.count { |player| GameRoomParticipants.bot?(player) }
  viewers = players.reject { |player| GameRoomParticipants.bot?(player) } + ['Watcher']
  h = type.new(players: players, viewers: viewers, options: options)
  h.advance(240)
  expected_p2p = GameRoomRealtime::P2POptions.session_options(options)
  assert(h.network.values.all? { |channel| channel.p2p_options == expected_p2p }, 'Clients did not configure table P2P')
  h.clients.each_value { |c| c.update_table_control('__control_epoch' => 'initial', '__table_owner' => 'Alice') }
  prior = h.network.transform_values(&:object_id)
  initial = players.dup
  bot = 'bot:7:8:en01'
  h.session['__initial_players'] = initial
  h.session['__table_owner'] = 'Watcher'
  h.players[0] = bot
  h.session['__seat_changes'] = [{'id' => 100, 'players' => h.players.dup}]
  game = type == PongHarness ? h.rules : h.game
  h.instance_variable_set(:@replay, game.replay(h.session, h.instance_variable_get(:@events), h.repository))
  control = {'__control_epoch' => 'handover-1', '__table_owner' => 'Watcher'}
  h.clients.each do |viewer, client|
    client.update_table_control(control)
    client.before_wait(h.replay, viewer)
  end
  assert(h.network.all? { |name, channel| prior[name] != channel.object_id }, 'Old peer channel survived authority change')
  assert(h.network.values.all? { |channel| channel.p2p_options == expected_p2p }, 'Handover lost table P2P')
  h.advance(260)
  assert(h.clients['Watcher'].host? && !h.clients['Alice'].host?, 'Coordinator did not change')
  assert(h.clients['Alice'].instance_variable_get(:@side) == nil, 'Replaced human still controls paddle')
  assert(h.clients['Watcher'].instance_variable_get(:@bots).length == original_bots + 1, 'New master did not take both old and replacement bots')
  assert(!h.clients['Bob'].instance_variable_get(:@required).include?('Alice'), 'Bot seat still requires absent human peer')
  if players.length == 4
    assert(h.clients.values.all? { |client| client.snapshot['teams'] == [0,0,1,1] }, 'Handover changed teams')
    assert(h.clients['Bob'].instance_variable_get(:@required).include?('Carol'), 'Handover lost the other human team')
  end
  assert(h.clients.values.all? { |client| !client.paused || client.snapshot['goal'] != nil }, "#{type}: new coordinator never synchronized")
  if type == PongHarness
    # First service belongs to replaced Alice. She is still connected and
    # sends observer status; that must not reset the bot's paddle every frame.
    h.advance(1000)
    assert(h.clients['Watcher'].engine.turn > 0, 'Connected replaced player prevents bot from serving')
  end
  h.players[0] = 'Alice'
  h.session['__seat_changes'] << {'id' => 200, 'players' => h.players.dup}
  h.instance_variable_set(:@replay, game.replay(h.session, h.instance_variable_get(:@events), h.repository))
  control = control.merge('__control_epoch' => 'handover-2')
  h.clients.each { |viewer, client| client.update_table_control(control); client.before_wait(h.replay, viewer) }
  h.advance(260)
  assert(h.clients['Alice'].instance_variable_get(:@side) == 0, 'Human seat was not restored')
  assert(h.clients['Watcher'].instance_variable_get(:@bots).length == original_bots, 'Restoration lost an original bot or retained the replacement')
  h.players[0], h.players[1] = h.players[1], h.players[0]
  h.session['__seat_changes'] << {'id' => 300, 'players' => h.players.dup}
  h.instance_variable_set(:@replay, game.replay(h.session, h.instance_variable_get(:@events), h.repository))
  control = control.merge('__control_epoch' => 'handover-3')
  h.clients.each { |viewer, client| client.update_table_control(control); client.before_wait(h.replay, viewer) }
  h.advance(260)
  assert(h.clients['Alice'].instance_variable_get(:@side) == 1 && h.clients['Bob'].instance_variable_get(:@side) == 0, 'Human swap retained the old paddle permissions')
  h.clients.each_value(&:close)
end
puts 'Realtime control: Single, mixed Doubles, channel isolation, spectator master, bots and return: OK'
