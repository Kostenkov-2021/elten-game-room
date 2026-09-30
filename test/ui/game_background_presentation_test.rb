require_relative "../support/background_help_game_screen"
require_relative "../../games/quiz_party"

# Only the host's outer loop is a peripheral double here. The screen,
# presentation, runner, game, repositories and in-memory native log are real.
module EltenAPI::UI
  def loop_update(value = :host, **_options); value; end
end
class BackgroundNativeScene
  include EltenAPI::UI
end
class ForbiddenCoveredLayout
  def method_missing(name, *); raise "Covered control access: #{name}"; end
end

$mainthread = $currentthread = Thread.current
$game_room_test_user = 'Alice'
original_play = GameRoomSounds.method(:play)
sounds = []
GameRoomSounds.define_singleton_method(:play) do |_program, cue|
  sounds << [cue, Thread.current]
  nil
end

def wait_packet(runner, scene)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
  until yield
    raise 'Covered native scene did not present received data' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    assert(scene.send(:loop_update, :preserved, check: true) == :preserved, 'Bridge changed native loop result')
    sleep 0.002
  end
end

begin
  h, screen = screen_fixture(GameRoomGames::FourInARow.new)
  spoken = []
  screen.define_singleton_method(:speak) { |text, **options| spoken << [text, options, Thread.current] }
  screen.instance_variable_set(:@game_services, {transport: h.transports['Alice']})
  screen.send(:process_new_events, h.replay('Alice'))
  screen.send(:event_presenter).instance_variable_set(:@last_seen_activity_id, 0)
  screen.instance_variable_set(:@history_index, 7)
  screen.instance_variable_set(:@chat_text, 'Szkic ąż')
  screen.instance_variable_set(:@layout, ForbiddenCoveredLayout.new)
  screen.send(:start_session_runner)
  runner = screen.instance_variable_get(:@session_runner)
  scene = BackgroundNativeScene.new
  Thread.new do
    $currentthread = Thread.current
    h.as('Alice') do
      # Normal full match: seven legal moves, win, and all cues before return.
      %w[Alice Bob Alice Bob Alice Bob Alice].each do |actor|
        h.write(actor, [GameRoomGames::EventCommand.new(action: 'drop', value: actor == 'Alice' ? '1' : '7')])
        event_id = h.events('Alice').last['__id'].to_i
        wait_packet(runner, scene) { screen.send(:event_presenter).instance_variable_get(:@last_seen_event_id) == event_id }
      end
      assert(h.replay('Alice').finished?, 'Fixture did not finish a normal match')
      assert(spoken.any? { |row| row[0] == h.game.result_text(h.replay('Alice')) }, 'Result waited for return')
      assert(sounds.length >= 7, 'Sound effects waited for return')
      assert(spoken.all? { |row| row[2] == Thread.current && row[1] == {stop: false, break_sequence: false} }, 'Speech ran in worker or interrupted reading')
      assert(sounds.all? { |row| row[1] == Thread.current }, 'Audio ran outside the active UI thread')
      assert(screen.instance_variable_get(:@history_index) == 7, 'Background moved history cursor')
      assert(screen.instance_variable_get(:@chat_text) == 'Szkic ąż', 'Background changed chat draft')

      # Rematch while still covered: the first new move is not discarded as
      # initial history, and an old/cached foreground replay cannot rewind it.
      old_session, old_replay = h.session, h.replay('Alice')
      h.start
      h.write('Alice', [GameRoomGames::EventCommand.new(action: 'drop', value: '3')])
      wait_packet(runner, scene) { screen.send(:event_presenter).instance_variable_get(:@presentation_session_id) == h.session['__id'] && screen.send(:event_presenter).instance_variable_get(:@last_seen_event_id) == h.events('Alice').last['__id'] }
      count = spoken.length
      screen.send(:process_new_events, old_replay, session: old_session, background: true)
      assert(spoken.length == count, 'Old snapshot replayed the previous game')
    end
  ensure
    $currentthread = $mainthread
  end.value
  counts = [spoken.length, sounds.length]
  screen.instance_variable_set(:@layout, nil)
  screen.instance_variable_set(:@session, h.session)
  screen.send(:prepare_presentation_session, h.session)
  screen.send(:process_new_events, h.replay('Alice'))
  5.times { scene.send(:loop_update) }
  assert([spoken.length, sounds.length] == counts, 'Returning repeated speech or sounds')
  packet = runner.presentation_snapshot
  assert(packet[:replay].history.none? { |entry| entry.kind == :turn }, 'UI mutated worker packet')
  screen.send(:stop_session_runner)
  assert(EltenAPI::UI.instance_variable_get(:@game_room_presenters).empty?, 'Closed screen retained a presenter')

  # A pending serialized sound continues while covered even with no new data.
  queue = GameRoomEventPresentation.new(clock: -> { 1.0 })
  finished = false
  sound = Object.new
  sound.define_singleton_method(:finished?) { finished }
  output = []
  queue.enqueue(replay: :first, start: -> { output << :first; [sound] }, finish: -> { output << :done })
  screen.send(:event_presenter).instance_variable_set(:@event_presentation, queue)
  snapshot_runner = Object.new
  snapshot_runner.define_singleton_method(:presentation_snapshot) { nil }
  screen.send(:present_background_session, snapshot_runner)
  assert(output == [:first], 'Serial cue was not started')
  finished = true
  screen.send(:present_background_session, snapshot_runner)
  assert(output == [:first, :done] && !queue.busy?, 'Serial completion waited for return/new event')

  # Repeated app reloads must reuse the host-owned bridge without callbacks to
  # a removed namespace. No registered game: native loops are a pure passthrough.
  bridge = EltenAPI::UI.instance_variable_get(:@game_room_presentation_bridge)
  file = File.expand_path("../../lib/game_background_presentation.rb", __dir__)
  closed_runner = Object.new
  closed_runner.define_singleton_method(:covered?) { false }
  20.times do
    space = Module.new
    space.module_eval(File.binread(file), file)
    p = space.const_get(:GameRoomBackgroundPresentation).attach(Object.new, program: Object.new, runner: closed_runner, key: [:reload])
    p.close
  end
  assert(EltenAPI::UI.ancestors.count { |entry| entry.equal?(bridge) } == 1, 'Reload stacked native loop bridges')
  assert(EltenAPI::UI.instance_variable_get(:@game_room_presenters).empty?, 'Reload retained an old namespace')
  assert(scene.send(:loop_update, :idle) == :idle, 'Idle bridge affected other screens')

  fresh = GameScreen.allocate
  fresh.instance_variable_set(:@repository, h.repositories['Alice'])
  assert(fresh.send(:prepare_presentation_session, {'__id'=>90}), 'Initial presentation session refused')
  assert(fresh.send(:prepare_presentation_session, {'__id'=>3}, background: true), 'Random lower rematch ID refused')
  assert(!fresh.send(:prepare_presentation_session, {'__id'=>90}), 'Old foreground session rolled back rematch')

  membership = GameScreen.allocate
  membership.instance_variable_set(:@membership_tracker, GameRoomSounds::MembershipTracker.new)
  membership.send(:present_session_membership, ['Alice'])
  fresh_room = {members: %w[Alice Bob]}
  room_runner = Object.new
  room_runner.define_singleton_method(:presentation_snapshot) { fresh_room }
  membership.instance_variable_set(:@session_runner, room_runner)
  before_sounds = sounds.length
  membership.send(:present_session_membership, fresh_room[:members])
  membership.send(:present_session_membership, ['Alice'])
  membership.send(:present_session_membership, fresh_room[:members])
  assert(sounds.drop(before_sounds).map(&:first) == ['connect'], 'Cached return caused phantom leave/join sounds')

  # Time announcements need no new network event. Exercise the real quiz
  # wording/keys with a controlled session clock, then return to the screen.
  timed = GameScreen.allocate
  timed.instance_variable_set(:@game, GameRoomGames::QuizParty.new)
  timed.send(:event_presenter).instance_variable_set(:@last_seen_event_id, 0)
  timed.send(:event_presenter).instance_variable_set(:@spoken_timer_announcements, {})
  timer_replay = Struct.new(:state).new({phase: :answering, deadline: 120, round: 1, position: 1})
  timed.instance_variable_set(:@background_timer_data, {session: {}, replay: timer_replay})
  session_time = 114
  clock = Object.new
  clock.define_singleton_method(:now) { |_session| session_time }
  clock.define_singleton_method(:now_f) { |_session| session_time.to_f }
  timed.instance_variable_set(:@action_clock, clock)
  timer_speech = []
  timed.define_singleton_method(:speak) { |message, **_options| timer_speech << message }
  timed.send(:present_background_session, snapshot_runner)
  assert(timer_speech.empty?, 'Quiz countdown announced too early')
  session_time = 115
  3.times { timed.send(:present_background_session, snapshot_runner) }
  assert(timer_speech == ['5 seconds remain.'], 'Covered quiz countdown waited for a new event or repeated')
  session_time = 120
  3.times { timed.send(:present_background_session, snapshot_runner) }
  timed.send(:announce_due_timers, timer_replay, now: session_time)
  assert(timer_speech == ['5 seconds remain.', 'Time is up.'], 'Quiz deadline was lost or repeated on return')
  aborted = {session: {'__aborted'=>true}}
  snapshot_runner.define_singleton_method(:presentation_snapshot) { aborted }
  timed.send(:present_background_session, snapshot_runner)
  assert(timed.instance_variable_get(:@background_timer_data).nil?, 'Aborted quiz retained its countdown')
ensure
  screen&.send(:stop_session_runner)
  GameRoomSounds.define_singleton_method(:play, original_play)
  $currentthread = $mainthread
end
puts 'PASS background presentation: complete match, active UI speech/audio, rematch, dedup, no controls, serial cues, cleanup and binary reloads'
