require_relative "../../support/pong_client"

commands = %w[perspective_first perspective_second perspective_third perspective_fourth]
[[0, 0, 1, 1], [0, 1, 0, 1], [1, 0, 1, 0]].each do |teams|
  h = PongHarness.new(players: %w[Alice Bob Carol Dave], options: {'team_size' => 2, 'team_seats' => teams})
  begin
    observer = h.clients['Watcher']
    surface = GameSurfaces.build(h.rules.surface_spec(h.replay, 'Watcher'))
    form = Form.new([surface.fields.first, EditBox.new('Chat')])
    observer.attach_view(form, surface)
    channel = observer.instance_variable_get(:@channel)
    before = Marshal.dump([observer.context_data, channel.sent, channel.event_sent])
    shortcuts = h.rules.game_shortcuts(h.replay, 'Watcher').select { |s| s.key.match?(/\A[1-4]\z/) }
    assert(shortcuts.map(&:key) == %w[1 2 3 4], 'doubles must expose all four observer keys')
    shortcuts.each_with_index do |shortcut, index|
      assert(shortcut.action_name == commands[index], 'observer key does not select its seat')
      surface.handle_command(shortcut.action_name)
      assert(observer.send(:audio_side) == index, "wrong perspective for seat #{index}")
      assert(observer.instance_variable_get(:@audio).updates.last[1] == index, 'audio kept the previous listener')
      assert($spoken_messages.last.include?(h.players[index]), 'perspective confirmation omitted the player')
      assert(!surface.input_active?(form) && observer.instance_variable_get(:@side) == nil, 'observer gained paddle control')
      observer.before_wait(h.replay, 'Watcher')
      assert(observer.send(:audio_side) == index, 'refresh lost the observed player')
    end
    assert(Marshal.dump([observer.context_data, channel.sent, channel.event_sent]) == before, 'local perspective changed network state')
    form.index = 1
    commands.each { |command| surface.handle_command(command) }
    assert(observer.send(:audio_side) == 3, 'chat commands changed the perspective')
    assert(form.fields[1].text.empty?, 'perspective changed chat text')
    h.accept_point('0:0')
    assert(observer.send(:audio_side) == 3, 'a point reset the fourth perspective')
    assert(observer.send(:observer_side, %w[Dave Carol Bob Alice]) == 0, 'perspective followed a seat instead of the player identity')
    h.players.each_with_index do |player, index|
      assert(h.rules.game_shortcuts(h.replay, player).none? { |s| s.key.match?(/\A[1-4]\z/) }, 'player received observer shortcuts')
      commands.each { |command| h.clients[player].send(:local_command, command) }
      assert(h.clients[player].send(:audio_side) == index, 'player changed perspective')
    end
  ensure
    h.close
  end
end

h = PongHarness.new
begin
  observer = h.clients['Watcher']
  surface = GameSurfaces.build(h.rules.surface_spec(h.replay, 'Watcher'))
  observer.attach_view(Form.new(surface.fields), surface)
  keys = h.rules.game_shortcuts(h.replay, 'Watcher').map(&:key).grep(/\A[1-4]\z/)
  assert(keys == %w[1 2], 'Single advertises nonexistent players')
  surface.handle_command('perspective_second')
  %w[perspective_third perspective_fourth].each { |command| surface.handle_command(command) }
  assert(observer.send(:audio_side) == 1, 'Single accepted an absent observer seat')
ensure
  h.close
end
puts 'PASS Pong observer 1-4: each player, arbitrary teams, local audio, identity, refresh, no chat/control/network side effects; Single remains 1-2'
