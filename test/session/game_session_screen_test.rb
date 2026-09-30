require_relative "../support/background_help_game_screen"

# The real GameScreen lifecycle with the new managed executor selected. Other
# tests above exercise the unchanged non-native/realtime paths as well.
$game_room_test_user = 'Alice'
[:help, :covered].each do |mode|
  h, screen = screen_fixture(GameRoomGames::FourInARow.new, bots: 1)
  screen.instance_variable_set(:@game_services, {transport: h.transports['Alice']})
  entered, finished, help = false, false, nil
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 6
  Form.driver = lambda do |form|
    raise 'Managed screen failed to progress' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    layout = screen.instance_variable_get(:@layout)
    unless entered
      entered = true
      if mode == :help
        form.show_game_room_help
        help = form.game_room_background_help_form
        help.fields.first.index = 9
      end
      h.write('Alice', [GameRoomGames::EventCommand.new(action: 'drop', value: '1')])
      if mode == :covered
        previous, $currentthread = $currentthread, Object.new
        begin
          sleep 0.01 until h.events('Alice').size >= 2 || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          assert(h.events('Alice').size == 2, 'covered GameScreen still controlled the bot loop')
        ensure
          $currentthread = previous
        end
      end
    end
    sleep 0.002 # yield to the real worker, not a fake synchronous Tasks block
    if h.events('Alice').size == 2 && screen.send(:event_presenter).instance_variable_get(:@last_seen_event_id).to_i >= h.events('Alice').last['__id'].to_i
      if help
        assert(form.game_room_background_help_form.equal?(help) && help.fields.first.index == 9, 'runner replaced help')
        form.clear_game_room_background_help
      end
      finished = true
      layout.back_button.trigger(:press)
    end
  end
  h.as('Alice') { assert(screen.run == :back, 'runner changed exit behavior') }
  assert(finished, 'runner did not refresh the screen')
  assert(screen.instance_variable_get(:@session_runner).nil?, 'screen retained its executor')
  assert(h.transports['Alice'].instance_variable_get(:@session_feeds).empty?, 'screen leaked its subscription')
  assert(h.events('Alice').size == 2, 'both screen and runner moved the bot')
end
puts 'GameScreen managed execution: foreground help, covered UI, single bot write and joined shutdown passed'
