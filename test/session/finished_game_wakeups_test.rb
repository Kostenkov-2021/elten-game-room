require_relative '../support/session_runner'
require_relative '../support/ui'
require_relative '../../lib/game_surfaces'
require_relative '../../lib/game_screen'

def drain_finished_game_sync(sync)
  20.times do
    return if sync.next_event.nil?
  end
  raise 'Foreground wake-ups did not settle'
end

begin
  h = NativeRoomHarness.new(game: GameRoomGames::TicTacToe.new, users: %w[Alice Bob])
  h.start
  transport, repository = h.transports.fetch('Bob'), h.repositories.fetch('Bob')
  sync = GameRoomSync::Controller.new(transport: transport, table_id: h.table['__id'], session_id: h.session['__id'])
  drain_finished_game_sync(sync)
  runner = runner_for(h, 'Bob', covered: -> { true })
  step(h, runner, 'Bob')
  screen = GameScreen.allocate
  {repository: repository, game: h.game, program: ProgramDouble.new(h.broker.endpoint('Bob')),
    game_services: {}, session: h.session, table: h.table, table_owner: 'Alice',
    synchronizer: sync, chat_sends: GameRoomUI::ChatSendBuffer.new}.each do |key, value|
    screen.instance_variable_set("@#{key}", value)
  end
  screen.define_singleton_method(:network_task) { |_title, **_options, &operation| operation.call }
  h.as('Bob') { screen.send(:prepare_presentation_session, h.session) }

  8.times do
    old_id = repository.session_id(h.session)
    [['Alice',0,0], ['Bob',0,1], ['Alice',1,0], ['Bob',1,1], ['Alice',2,0]].each do |user, x, y|
      h.submit(user, {'kind'=>'grid','action'=>'select','x'=>x,'y'=>y})
      step(h, runner, 'Bob')
    end
    h.assert_converged('finished rematch', expected_count: 5)
    assert(h.replay('Alice').finished? && h.replay('Bob').finished?, 'Rematch was not normally finished')
    assert(runner.instance_variable_get(:@replay).finished?, 'Covered runner missed the result')
    assert(runner.instance_variable_get(:@feed).consume_game_change(old_id).nil?, 'Runner did not drain its independent feed')
    h.start
    step(h, runner, 'Bob', count: 2)
    event = sync.next_event
    assert(event&.kind == :game_started && event.session_id == h.session['__id'], 'Start did not precede historical changes')
    screen.instance_variable_set(:@new_session_id, event.session_id)
    h.as('Bob') { assert(screen.send(:switch_to_new_session), 'Screen did not select the verified rematch') }
    drain_finished_game_sync(sync)
    assert(h.core.trimmed_through.positive? && h.core.entries.length == 2, 'Native fixture did not trim previous games')
    assert(transport.instance_variable_get(:@pending_game_changes).empty?, 'Finished-game wakeups survive normal rematches and foreground drain')
  end
  puts 'PASS eight complete native-fixture rematches, covered runner, foreground switch/drain and trimmed history without retained game wake-ups'
ensure
  runner&.close
end
