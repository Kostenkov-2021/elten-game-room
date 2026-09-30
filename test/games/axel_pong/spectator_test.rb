require_relative "../../support/pong_client"

h = PongHarness.new
observer = h.clients['Watcher']
surface = GameSurfaces.build(h.rules.surface_spec(h.replay, 'Watcher'))
form = Form.new([surface.fields.first, EditBox.new('Chat')])
observer.attach_view(form, surface)
audio = observer.instance_variable_get(:@audio)
channel = observer.instance_variable_get(:@channel)
before = Marshal.dump([observer.context_data, channel.sent, channel.event_sent])
assert(observer.send(:audio_side) == 0, 'observer default changed')
surface.handle_command('perspective_second')
assert(observer.send(:audio_side) == 1 && audio.updates.last[1] == 1, 'second perspective ignored')
expected = observer.send(:_, 'Perspective: %{player}.') % { player: 'Bob' }
assert($spoken_messages.last == expected, 'observer confirmation wrong')
assert(observer.instance_variable_get(:@side) == nil && !surface.input_active?(form), 'observer received paddle authority')
surface.handle_command('perspective_second')
observer.before_wait(h.replay, 'Watcher')
assert(observer.send(:audio_side) == 1, 'refresh lost selected player')
assert(Marshal.dump([observer.context_data, channel.sent, channel.event_sent]) == before, 'perspective sent gameplay data')
form.index = 1
surface.handle_command('perspective_first')
assert(observer.send(:audio_side) == 1, 'chat digit changed perspective')
form.index = 0
surface.handle_command('perspective_first')
assert(observer.send(:audio_side) == 0, 'first perspective ignored')
observer.instance_variable_set(:@observed_player, 'Bob')
assert(observer.send(:observer_side, %w[Bob Alice]) == 0, 'perspective did not follow selected player identity')
assert(observer.send(:observer_side, %w[Carol Dave]) == 0 && observer.instance_variable_get(:@observed_player) == 'Carol', 'removed player not reset safely')
assert(h.rules.game_shortcuts(h.replay, 'Watcher').select { |s| %w[1 2].include?(s.key) }.length == 2, 'observer help incomplete')
assert(h.rules.game_shortcuts(h.replay, 'Bob').none? { |s| %w[1 2].include?(s.key) }, 'player received observer shortcuts')
h.clients['Bob'].send(:local_command, 'perspective_first')
assert(h.clients['Bob'].send(:audio_side) == 1, 'player perspective changed')
h.close
puts 'PASS Pong spectator: both views, same-player refresh, changed lineup, no control/network mutation, playfield-only keys'
