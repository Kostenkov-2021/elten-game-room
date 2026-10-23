require_relative '../support/pong_client'

settings = {'background_table_speech' => false}
previous_settings = Program.method(:normalized_settings) if Program.respond_to?(:normalized_settings)
Program.define_singleton_method(:normalized_settings) { settings }
previous_controls = [$activecontrols, $lastactivecontrols]
h = nil

begin
  [false, true].product([false, true]).each do |covered, enabled|
    settings['background_table_speech'] = enabled
    $activecontrols = []
    $lastactivecontrols = covered ? [Object.new] : []
    h = PongHarness.new
    spoken = h.clients.to_h { |name, _client| [name, []] }
    h.clients.each do |name, client|
      client.define_singleton_method(:speak) { |message, **options| spoken[name] << [message, options] }
    end
    h.advance(300)
    spoken.each_value(&:clear)
    owner = h.clients.fetch('Alice')
    caller = h.clients.fetch(h.players.fetch(1 - owner.engine.server))
    assert(caller.request_hurry, 'Normal opponent warning was rejected')
    h.advance(2)
    expected = covered && !enabled ? 0 : 1
    assert(spoken.values.all? { |messages| messages.size == expected },
      "Warning speech ignored coverage/settings: #{[covered, enabled, spoken].inspect}")
    assert(owner.instance_variable_get(:@hurry_until) > h.now,
      'Speech mute also cancelled the authoritative warning deadline')
    if covered && enabled
      assert(spoken.values.all? { |messages| messages.first.last == {stop: false, break_sequence: false} },
        'Enabled background warning interrupted the foreground reader')
    end
    $lastactivecontrols = []
    h.advance(2)
    assert(spoken.values.all? { |messages| messages.size == expected },
      'Returning to the game replayed a muted or delivered warning')
    h.advance(640)
    assert(owner.context_data.fetch('pong_point').to_s.end_with?(':timeout'),
      'Warning no longer produced the normal timeout point')
    h.close
    h = nil
  end
ensure
  h&.close
  $activecontrols, $lastactivecontrols = previous_controls
  if previous_settings
    Program.define_singleton_method(:normalized_settings, previous_settings)
  else
    Program.singleton_class.remove_method(:normalized_settings)
  end
end
puts 'PASS Pong warning: foreground/background policy, players and observer, non-interruption, no backlog and unchanged timeout'
