require_relative "../support/background_help_game_screen"

settings = {'background_table_speech'=>false, 'background_turn_sound'=>true}
ProgramDouble.define_singleton_method(:normalized_settings) { settings }
original_play = GameRoomSounds.method(:play)
sounds = []
pending_sound = nil
GameRoomSounds.define_singleton_method(:play) { |_program, cue| sounds << cue; cue == 'ding' ? nil : pending_sound }
$game_room_test_user = 'Alice'
$activecontrols = []
begin
  h, screen = screen_fixture(GameRoomGames::FourInARow.new)
  covered = true
  screen.instance_variable_set(:@runner_covered, -> { covered })
  spoken = []
  screen.define_singleton_method(:speak) { |message, **_options| spoken << message }
  screen.send(:process_new_events, h.replay('Alice'))
  assert(sounds.count('ding') == 1, 'Initial own decision behind another window was not signalled')
  h.write('Alice', [GameRoomGames::EventCommand.new(action: 'drop', value: '1')])
  screen.send(:process_new_events, h.replay('Alice'))
  assert(sounds.count('ding') == 1, 'Opponent turn caused own-turn cue')
  h.write('Bob', [GameRoomGames::EventCommand.new(action: 'drop', value: '7')])
  4.times { screen.send(:process_new_events, h.replay('Alice')) }
  assert(sounds.count('ding') == 2 && spoken.empty?, 'Own-turn cue duplicated or automatic speech ignored mute')
  assert(h.replay('Alice').accepted_events.size == 2, 'Mute stopped the model')
  history = screen.send(:combined_history_items, h.replay('Alice'))
  assert(history.any? { |item| item.to_s.include?('Bob') }, 'Muted event disappeared from manual history')
  covered = false
  screen.send(:process_new_events, h.replay('Alice'))
  assert(spoken.empty? && sounds.count('ding') == 2, 'Returning replayed muted messages or cue')
  h.write('Alice', [GameRoomGames::EventCommand.new(action: 'drop', value: '1')])
  screen.send(:process_new_events, h.replay('Alice'))
  assert(!spoken.empty?, 'Background mute also muted normal foreground play')
  covered = true
  settings['background_turn_sound'] = false
  h.write('Bob', [GameRoomGames::EventCommand.new(action: 'drop', value: '7')])
  screen.send(:process_new_events, h.replay('Alice'))
  assert(sounds.count('ding') == 2, 'Turn-cue setting was not applied')
  settings['background_turn_sound'] = true
  [['Alice', '2'], ['Bob', '6'], ['Alice', '3']].each do |actor, column|
    h.write(actor, [GameRoomGames::EventCommand.new(action: 'drop', value: column)])
  end
  screen.send(:process_new_events, h.replay('Alice'))
  assert(sounds.count('ding') == 2, 'Catch-up rang for an own turn that already ended')
  screen.send(:event_presenter).instance_variable_set(:@decision_presentation_started, false)
  screen.send(:event_presenter).instance_variable_set(:@last_seen_event_id, 0)
  screen.send(:process_new_events, h.replay('Alice'))
  assert(sounds.count('ding') == 2, 'Initial catch-up rang for a past first turn')
  [['Bob', '6'], ['Alice', '5'], ['Bob', '4']].each do |actor, column|
    h.write(actor, [GameRoomGames::EventCommand.new(action: 'drop', value: column)])
  end
  screen.send(:process_new_events, h.replay('Alice'))
  assert(sounds.count('ding') == 3, 'One batch rang for multiple past turns instead of the current decision')

  game = GameRoomGames::FourInARow.new
  game.define_singleton_method(:serial_event_presentation?) { true }
  serial_h, serial_screen = screen_fixture(game)
  serial_screen.instance_variable_set(:@runner_covered, -> { true })
  serial_screen.send(:process_new_events, serial_h.replay('Alice'))
  baseline = sounds.count('ding')
  sound_done = false
  pending_sound = Object.new
  pending_sound.define_singleton_method(:finished?) { sound_done }
  pending_sound.define_singleton_method(:length) { 1.0 }
  [['Alice', '1'], ['Bob', '7'], ['Alice', '2']].each do |actor, column|
    serial_h.write(actor, [GameRoomGames::EventCommand.new(action: 'drop', value: column)])
    serial_screen.send(:process_new_events, serial_h.replay('Alice'))
  end
  assert(serial_screen.send(:event_presentation_busy?), 'Serial cue fixture never waited for audio')
  sound_done = true
  serial_screen.send(:process_new_events, serial_h.replay('Alice'))
  assert(sounds.count('ding') == baseline, 'Delayed sound queue rang for a turn already superseded')
  serial_h.write('Bob', [GameRoomGames::EventCommand.new(action: 'drop', value: '6')])
  serial_screen.send(:process_new_events, serial_h.replay('Alice'))
  assert(sounds.count('ding') == baseline + 1, 'Serial completion lost the currently pending decision')

  # Rejoining does not reclaim a bot-controlled seat, including its private
  # input or background turn cue. Only explicit restoration does so.
  controlled_h, controlled_screen = screen_fixture(GameRoomGames::FourInARow.new)
  controlled_screen.instance_variable_set(:@runner_covered, -> { true })
  session = controlled_screen.instance_variable_get(:@session)
  bot = 'bot:1:1:pl20'
  session['__initial_players'] = session['__players'].dup
  session['__players'] = [bot, 'Bob']
  session['__seat_changes'] = [{'id' => 1, 'players' => session['__players'].dup}]
  replaced_replay = controlled_h.game.replay(session, [], controlled_h.repositories['Alice'])
  controlled_screen.instance_variable_set(:@session_runner, nil)
  baseline = sounds.count('ding')
  controlled_screen.send(:present_required_decision, nil, replaced_replay)
  assert(sounds.count('ding') == baseline, 'Replaced human still received a turn cue')
  controlled_screen.instance_variable_set(:@selected_surface_action, {id: 'drop', value: '1'})
  said = []
  controlled_screen.define_singleton_method(:speak) { |message, **_options| said << message }
  assert(controlled_screen.send(:submit_action, replaced_replay) == false, 'Replaced human submitted an action')
  assert(said == ['You are observing the game.'], 'Replaced human got no explanation')
  session['__players'] = session['__initial_players'].dup
  session['__seat_changes'] = []
  controlled_screen.send(:present_required_decision, nil, controlled_h.replay('Alice'))
  assert(sounds.count('ding') == baseline + 1, 'Restored human lost their turn cue')
ensure
  screen&.send(:stop_session_runner)
  serial_screen&.send(:stop_session_runner)
  controlled_screen&.send(:stop_session_runner)
  GameRoomSounds.define_singleton_method(:play, original_play)
  ProgramDouble.singleton_class.remove_method(:normalized_settings)
end
puts 'PASS decision presentation: initial/current turns only, batch deduplication, stale audio and catch-up suppression, mute preserves history/model'
