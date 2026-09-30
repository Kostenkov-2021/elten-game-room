require_relative "../support/ui"
require_relative "../support/log"
require_relative "../support/native_room_harness"
class Program
  def self.server_app(**_options); end
  def self.app_runtime; nil; end
end
module EltenAPI::Tasks
  def self.run(**_options); yield; end
end
module EltenAPI::UI
  def loop_update; :native; end
end
require_relative "../../__app"
class TableNativeScene
  include EltenAPI::UI
end

def await_table(scene, message)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 4
  until yield
    raise message if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    assert(scene.send(:loop_update) == :native, 'Changed the native loop result')
    sleep 0.003
  end
end

$mainthread = $currentthread = Thread.current
$game_room_test_user = 'Alice'
h = NativeRoomHarness.new(game: GameRoomGames::TicTacToe.new, users: ['Alice'], bots: 1)
h.add_client('Bob')
program = ProgramDouble.new(h.broker.endpoint('Alice'))
app = EltenGameRoom.new
EltenGameRoom.remember_settings(EltenGameRoom::DEFAULT_SETTINGS)
app.instance_variable_set(:@transport, h.transports['Alice'])
app.instance_variable_set(:@games, h.repositories['Alice'])
activity = TableActivityRepository.new(transport: h.transports['Alice'], server_tables: {})
guest_activity = TableActivityRepository.new(transport: h.transports['Bob'], server_tables: {})
lobby = LobbyRepository.new(program, transport: h.transports['Alice'], server_tables: {}, activity_repository: activity)
app.instance_variable_set(:@table_activity, activity)
app.instance_variable_set(:@lobby, lobby)
app.define_singleton_method(:play_game_sounds) { |cues| cues.each { |cue| play_sound_from_asset(cue) } }
spoken, sounds = [], []
app.define_singleton_method(:speak) { |message, **opts| spoken << [message, Thread.current, opts] }
app.define_singleton_method(:play_sound_from_asset) { |cue, **_opts| sounds << [cue, Thread.current]; nil }
app.define_singleton_method(:game_room_sound_enabled?) { |_cue| true }
app.define_singleton_method(:game_room_sound_volume) { |_cue| 1.0 }
tracker = app.send(:room_membership_tracker, h.table)
tracker.observe(['Alice'])
covered = false
screens = []
monitor = GameRoomTableBackground.new(program: app, transport: h.transports['Alice'], repository: h.repositories['Alice'],
  lobby: lobby, activity_repository: activity, table: h.table, session_id: 0, activity_cursor: 0,
  covered: -> { covered }, screen_builder: ->(session, game, table) {
    app.send(:build_game_screen, session, game, table: table, layout: nil).tap do |screen|
      screen.define_singleton_method(:speak) { |message, **opts| spoken << [message, Thread.current, opts] }
      screens << screen
    end
  }).start
scene = TableNativeScene.new
begin
  sleep 0.12
  assert(monitor.presentation_snapshot.nil?, 'Waiting-room worker read/presented while foreground')
  covered = true
  assert(h.join('Bob'), 'Guest could not join')
  h.as('Bob') { guest_activity.append(table: h.table, kind: 'joined', actor: 'Bob') }
  await_table(scene, 'No membership/audio while covered') { sounds.any? { |row| row.first == 'connect' } && spoken.any? { |row| row.first.include?('Bob joined') } }
  h.as('Bob') { guest_activity.append(table: h.table, kind: 'chat', actor: 'Bob', message: 'Covered chat') }
  await_table(scene, 'Chat waited for return') { spoken.any? { |row| row.first.include?('Covered chat') } }
  assert(sounds.any? { |row| row.first == 'chatmsg' }, 'Chat audio waited for return')
  session = h.repositories['Alice'].start_session(table: h.table, game: h.game.id,
    players: ['Alice'] + lobby.snapshot_for(h.table).bots, options: '{}')
  await_table(scene, 'Game start waited for return') { screens.size == 1 && spoken.any? { |row| row.first.start_with?('Game started:') } }
  screen = screens.first
  runner = screen.instance_variable_get(:@session_runner)
  assert(screen.instance_variable_get(:@layout).nil?, 'Covered start constructed a form')
  repo = h.repositories['Alice']
  replay = h.game.replay(session, repo.snapshot_for(session).events, repo)
  status, plan = h.game.action_for(h.game.legal_actions(replay, 'Alice').first, replay, 'Alice')
  assert(status == :ok, 'Fixture action is illegal')
  repo.append_events(session: session, sequence: 1, events: plan.events, actor: 'Alice')
  await_table(scene, 'Newly started game/bot did not run while covered') {
    screen.send(:event_presenter).instance_variable_get(:@last_seen_event_id).to_i > repo.snapshot_for(session).events.first['__id'].to_i &&
      repo.snapshot_for(session).events.length == 2
  }
  assert(screens.length == 1, 'Duplicate screen/runner on repeated packets')
  assert(spoken.all? { |row| row[1] == Thread.current && row[2] == {stop: false, break_sequence: false} }, 'Interrupted speech or used worker UI')
  assert(sounds.all? { |row| row[1] == Thread.current }, 'Audio called from worker')
  count = [spoken.size, sounds.size]
  cursor = monitor.activity_cursor
  transferred = monitor.take_game_screen
  monitor.close
  monitor.join
  assert(transferred.equal?(screen) && !runner.closed?, 'Handover lost/closed active executor')
  covered = false
  # A last chat arrives after uncovering but before the table's foreground
  # refresh/adoption. That refresh owns the announcement, not both screens.
  h.as('Bob') { guest_activity.append(table: h.table, kind: 'chat', actor: 'Bob', message: 'At handover') }
  entries = activity.entries_for(h.table)
  next_cursor = app.send(:announce_new_table_activity, entries, after_id: cursor)
  current_replay = h.game.replay(session, repo.snapshot_for(session).events, repo)
  layout = GameRoomLayout::Screen.new(view_spec: h.game.waiting_view_spec('Alice'), history_items: [],
    user_items: [], users_header: 'Users', phase: :waiting, own_table: true)
  layout.activity_cursor = next_cursor
  screen.attach_table_layout(layout)
  screen.send(:process_new_table_activity, current_replay, entries: entries, background: true)
  assert(spoken.count { |row| row.first.include?('At handover') } == 1, 'Handover repeated last chat')
  count = [spoken.size, sounds.size]
  screen.send(:process_new_events, h.game.replay(session, repo.snapshot_for(session).events, repo))
  app.send(:announce_new_table_activity, entries, after_id: next_cursor)
  screen.send(:start_session_runner)
  assert(screen.instance_variable_get(:@session_runner).equal?(runner), 'Foreground created a second executor')
  assert([spoken.size, sounds.size] == count, 'Return repeated announcements/audio')
  screen.close_covered_session
  assert(EltenAPI::UI.instance_variable_get(:@game_room_presenters).empty?, 'Presenter leaked')
  assert(h.transports['Alice'].instance_variable_get(:@session_feeds).empty?, 'Feed leaked')
  puts 'PASS waiting table: join/chat speech and audio, covered game start/bot, no controls, one executor and quiet ownership transfer'
ensure
  warn({spoken: spoken, sounds: sounds, packet: monitor.presentation_snapshot, log: (Log.messages if Log.respond_to?(:messages))}.inspect) if $!
  monitor.close
  monitor.join
  screens.each(&:close_covered_session)
end

# A previously running/aborted match is not a newly started game. Read only on
# notifications, keep the existing retry/backoff and do not flood after errors.
covered = true
old_count = screens.length
monitor = GameRoomTableBackground.new(program: app, transport: h.transports['Alice'], repository: h.repositories['Alice'],
  lobby: lobby, activity_repository: activity, table: h.table, session_id: session['__id'], activity_cursor: cursor,
  covered: -> { covered }, screen_builder: ->(*) { raise 'Reopened an old match' })
reads = 0
original_snapshot = lobby.method(:snapshot_for)
fail_read = false
lobby.define_singleton_method(:snapshot_for) do |*args|
  reads += 1
  raise EltenAPI::LiveSessions::TimeoutError, 'Controlled offline test' if fail_read
  original_snapshot.call(*args)
end
begin
  monitor.step
  monitor.present_background_session(monitor)
  count = [spoken.size, sounds.size]
  30.times { monitor.step; monitor.present_background_session(monitor) }
  assert(reads == 1 && [spoken.size, sounds.size] == count && screens.length == old_count,
    'Idle/old session caused extra requests or announcements')
  now = 100.0
  monitor.instance_variable_get(:@sync).instance_variable_set(:@clock, -> { now })
  feed = monitor.instance_variable_get(:@feed)
  fail_read = true
  feed.notify(:table, true)
  monitor.step
  50.times { feed.notify(:table, true); monitor.step }
  assert(reads == 2, 'Notifications bypassed error backoff')
  fail_read = false
  now += 31
  monitor.step
  assert(reads == 3, 'Did not recover without keyboard input')
  monitor.present_background_session(monitor)
  feed.notify(:closed, true)
  monitor.step
  20.times { monitor.present_background_session(monitor); monitor.step }
  assert(spoken.count { |row| row.first == 'This table is no longer available.' } == 1,
    'Closure was missing or repeated')
  assert(reads == 3, 'Confirmed closure kept reading the room')
  puts 'PASS waiting table: existing session, no polling, retry/backoff, self-recovery and one closure announcement'
ensure
  monitor.close
  lobby.define_singleton_method(:snapshot_for, original_snapshot)
end

# Realtime now starts behind Messages too. The waiting room hands over this
# exact screen rather than creating a second game when its form returns.
started_screen, starts = Object.new, []
started_screen.define_singleton_method(:start_covered_session) { |**args| starts << args }
started_screen.define_singleton_method(:table_activity_cursor) { cursor }
started_screen.define_singleton_method(:close_covered_session) { nil }
monitor = GameRoomTableBackground.new(program: app, transport: h.transports['Alice'], repository: h.repositories['Alice'],
  lobby: lobby, activity_repository: activity, table: h.table, session_id: 0, activity_cursor: cursor,
  covered: -> { true }, screen_builder: ->(*) { started_screen })
packet = {room: lobby.snapshot_for(h.table), session: session.merge('game' => 'axel_pong'), activity: []}
begin
  monitor.instance_variable_set(:@packet, packet)
  count = spoken.size
  3.times { monitor.present_background_session(monitor) }
  assert(spoken.size == count + 1 && monitor.take_game_screen.equal?(started_screen) && starts.length == 1,
    'Realtime start was lost/repeated or created multiple screens')
  puts 'PASS waiting table: realtime start once and same screen handed over'
ensure
  monitor.close
end

restored = app.send(:build_game_screen, session.merge('__event_id_base' => 700), h.game, table: h.table, layout: nil)
restored.define_singleton_method(:start_session_runner) { nil }
restored.start_covered_session(covered: -> { true }, activity_cursor: 10)
assert(restored.send(:event_presenter).instance_variable_get(:@last_seen_event_id) == 700, 'Restored game would repeat archived moves')
puts 'PASS waiting table: restored game skips archived events'

# Internal failures must not turn the monitor into a 20 Hz failing reader.
# Keep the native scene untouched; the original exception reaches Game Room
# when its foreground owner resumes, without mutating/closing the room.
monitor = GameRoomTableBackground.new(program: app, transport: h.transports['Alice'], repository: h.repositories['Alice'],
  lobby: lobby, activity_repository: activity, table: h.table, session_id: session['__id'], activity_cursor: cursor,
  covered: -> { true }, screen_builder: ->(*) { raise 'unexpected game creation' })
reads = 0
failure = NoMethodError.new('controlled waiting-room bug')
failure.set_backtrace(['waiting-room.rb:42'])
original_snapshot = lobby.method(:snapshot_for)
lobby.define_singleton_method(:snapshot_for) { |*| reads += 1; raise failure }
pushes = h.view('Alice').calls[:push]
begin
  100.times { monitor.step; monitor.present_background_session(monitor) }
  assert(reads == 1 && !monitor.instance_variable_get(:@sync).recovery_pending?, 'internal waiting-room fault was retried')
  assert(!h.core.closed && h.view('Alice').calls[:push] == pushes, 'fault changed the server room')
  begin
    monitor.take_game_screen
    raise 'foreground did not receive the waiting-room fault'
  rescue NoMethodError => error
    assert(error.equal?(failure), 'foreground lost the original exception')
  end
ensure
  monitor.close
  lobby.define_singleton_method(:snapshot_for, original_snapshot)
end
puts 'PASS waiting table: terminal internal error, no retry/write/close, original foreground exception'
