require_relative "../support/native_room_harness"
require_relative "../support/ui"
require_relative "../support/log"
require_relative "../../lib/game_surfaces"
require_relative "../../lib/game_screen"
require_relative "../../lib/game_content"
require_relative "../../content/languages"
require_relative "../../content/quiz_pl_wikidata"
require_relative "../../games/quiz_party"

module EltenAPI::Tasks
  class Cancelled < StandardError; end unless const_defined?(:Cancelled)
  def self.run(**_options)
    token = Object.new
    def token.raise_if_cancelled!; end
    yield nil, token
  end
end

module RecoveryClock
  def now; Time.at($recovery_now); end
end
$recovery_now = 1000
Time.singleton_class.prepend(RecoveryClock)

# Advance the monotonic session-clock estimate along with virtual wall time.
# Production uses monotonic elapsed time; mocking only Time.now leaves the
# replay clock stuck at 1000 when a question closes at virtual time 1035.
module RecoveryHarnessClock
  def initialize(**options)
    super
    transports.each_value do |transport|
      store = transport.instance_variable_get(:@live_store)
      raise 'missing native live store in recovery fixture' unless store.is_a?(GameRoomLiveSessionStore)
      store.instance_variable_set(:@record_clock, GameRoomSessionClock.new(
        sample: -> { nil }, wall: -> { $recovery_now.to_f }, elapsed: -> { $recovery_now.to_f }))
    end
  end
end
NativeRoomHarness.prepend(RecoveryHarnessClock)

def controller_for(h, user, clock)
  sync = GameRoomSync::Controller.new(transport: h.transports[user],
    table_id: h.table["__id"], session_id: h.session["__id"], clock: -> { clock[0] })
  10.times { sync.next_event }
  sync.synchronized!
end

def screen_for(h, user, sync, context: nil)
  screen = GameScreen.allocate
  values = { repository: h.repositories[user], game: h.game, session: h.session,
    table: h.table, table_owner: h.users.first, synchronizer: sync, pending_event_ids: [],
    bot_turn_controller: h.repositories[user].bot_turn_controller(h.table["__id"]),
    room_snapshot_provider: -> { data = h.transports[user].room_snapshot(h.table); data && LobbyRepository::TableSnapshot.new(**data) } }
  values.each { |key, value| screen.instance_variable_set("@#{key}", value) }
  screen.define_singleton_method(:alert) { |text| (@alerts ||= []) << text }
  screen.define_singleton_method(:action_context) { context } if context
  screen.define_singleton_method(:game_recipients) { [] }
  screen
end

def freeze_metadata(h)
  h.broker.automatic_delivery = false
  h.users.each do |user|
    view = h.view(user)
    state = view.stack_state.dup
    view.define_singleton_method(:stack_state) { state.dup }
  end
end

checks = 0
check = lambda do |name, &block|
  block.call
  checks += 1
  puts "PASS: #{name}"
end

[:before, :after].each do |fault|
  check.call("four readers: #{fault} write failure retains one exact operation") do
    h = NativeRoomHarness.new
    h.start
    freeze_metadata(h)
    clock = [0.0]
    sync = controller_for(h, "Alice", clock)
    packet = GameRoomGames::EventCommand.new(action: "tick", value: "chosen random value")
    view = h.view("Alice")
    view.fail_next_push = fault
    begin
      sync.synchronize { h.write("Alice", [packet], sequence: 1) }
      raise "failure was not injected"
    rescue EltenAPI::LiveSessions::TimeoutError
    end
    first = view.instance_variable_get(:@push_attempts).last
    begin
      h.write("Alice", [GameRoomGames::EventCommand.new(action: "tick", value: "replacement")], sequence: 1)
      raise "a new plan replaced the uncertain one"
    rescue GameRoomNetworkErrors::PendingMove
    end
    assert(sync.next_event.nil?, "retry ignored the backoff")
    pushes = view.calls[:push]
    clock[0] = 31
    assert(sync.next_event.kind == :recovery, "no retry after failure")
    sync.synchronize { h.events("Alice") }
    attempts = view.instance_variable_get(:@push_attempts)
    assert(view.calls[:push] == pushes + (fault == :before ? 1 : 0), "wrong number of retry writes")
    assert(attempts.last == first, "retry changed UUID or packet")
    h.broker.deliver(duplicate: true)
    h.assert_converged("#{fault} failure", expected_count: 1)
    assert(h.events("Bob").first["value"] == packet.value, "random plan was replaced")
    before = h.users.to_h { |u| [u, h.view(u).calls.dup] }
    100.times { sync.next_event; h.events("Alice") }
    assert(h.users.all? { |u| h.view(u).calls == before[u] }, "healthy state started polling")
  end
end

check.call("late original and retry are applied once even without server deduplication") do
  h = NativeRoomHarness.new
  h.start
  h.broker.automatic_delivery = false
  view = h.view("Alice")
  view.fail_next_push = :before
  begin
    h.write("Alice", [GameRoomGames::EventCommand.new(action: "tick", value: "once")])
  rescue EltenAPI::LiveSessions::TimeoutError
  end
  original = view.instance_variable_get(:@push_attempts).last
  h.transports["Alice"].reconcile(h.table["__id"])
  # The first timed-out HTTP request now arrives, despite the earlier empty
  # read. Deliberately remove the fake server's UUID cache for this probe.
  h.core.dedup.delete(["Alice", original[0]])
  view.stack_push(original[1], message_id: original[0])
  h.broker.deliver(duplicate: true)
  h.assert_converged("late duplicate", expected_count: 1)
  h.write("Bob", [GameRoomGames::EventCommand.new(action: "tick", value: "after duplicate")])
  h.broker.deliver
  h.assert_converged("cursor crossed duplicate sequence", expected_count: 2)
end

check.call("permanent server rejection is not queued; closing cancels an uncertain move") do
  h = NativeRoomHarness.new
  h.start
  view = h.view("Alice")
  view.fail_next_push = EltenAPI::LiveSessions::StackPacketTooLarge.new("rejected")
  begin
    h.write("Alice", [GameRoomGames::EventCommand.new(action: "tick", value: "rejected")])
  rescue EltenAPI::LiveSessions::StackPacketTooLarge
  end
  pushes = view.calls[:push]
  h.transports["Alice"].reconcile(h.table["__id"])
  assert(view.calls[:push] == pushes, "definitive rejection was retried")
  view.fail_next_push = :before
  begin
    h.write("Alice", [GameRoomGames::EventCommand.new(action: "tick", value: "cancelled by exit")])
  rescue EltenAPI::LiveSessions::TimeoutError
  end
  h.transports["Alice"].deactivate_table(table_id: h.table["__id"])
  pushes = view.calls[:push]
  h.transports["Alice"].reconcile(h.table["__id"])
  assert(view.calls[:push] == pushes, "a departed player retried a move")
end

check.call("late original preceding retry converges despite out-of-order own acknowledgement") do
  h = NativeRoomHarness.new
  h.start
  h.broker.automatic_delivery = false
  view = h.view("Alice")
  view.fail_next_push = :before
  begin
    h.write("Alice", [GameRoomGames::EventCommand.new(action: "tick", value: "one identity")])
  rescue EltenAPI::LiveSessions::TimeoutError
  end
  id, packet = view.instance_variable_get(:@push_attempts).last
  reader = view.method(:stack_read)
  writer = view.method(:stack_push)
  delivered_original = false
  view.define_singleton_method(:stack_read) do |**args|
    page = reader.call(**args)
    if !delivered_original
      delivered_original = true
      # The read was empty, but the original commits before the retry.
      writer.call(packet, message_id: id)
      h.core.dedup.delete(["Alice", id])
    end
    page
  end
  h.transports["Alice"].reconcile(h.table["__id"])
  h.broker.deliver(duplicate: true)
  h.assert_converged("original preceding retry", expected_count: 1)
end

check.call("ambiguous acknowledgement uses read-back, not the stack tail as its own position") do
  h = NativeRoomHarness.new
  h.start
  freeze_metadata(h)
  view = h.view("Alice")
  writer = view.method(:stack_push)
  view.define_singleton_method(:stack_push) do |*args, **kwargs|
    writer.call(*args, **kwargs)
    { "stack" => { "last_seq" => 999999 } }
  end
  begin
    h.write("Alice", [GameRoomGames::EventCommand.new(action: "tick", value: "ambiguous reply")])
    raise "ambiguous position was presented as confirmed"
  rescue GameRoomNetworkErrors::UncertainWrite
  end
  pushes = view.calls[:push]
  h.transports["Alice"].reconcile(h.table["__id"])
  assert(view.calls[:push] == pushes, "ambiguous but stored operation was resent")
  h.broker.deliver
  h.assert_converged("ambiguous reply", expected_count: 1)
  assert(h.events("Alice").first["__id"] < 999999, "foreign stack tail became an event ID")
end

check.call("starting another game discards an unresolved move for the previous game") do
  h = NativeRoomHarness.new
  h.start
  h.view("Bob").fail_next_push = :before
  begin
    h.write("Bob", [GameRoomGames::EventCommand.new(action: "tick", value: "old game")])
  rescue EltenAPI::LiveSessions::TimeoutError
  end
  h.start
  pushes = h.view("Bob").calls[:push]
  h.transports["Bob"].reconcile(h.table["__id"])
  assert(h.view("Bob").calls[:push] == pushes, "an old-game command was replayed into a new game")
  h.write("Bob", [GameRoomGames::EventCommand.new(action: "tick", value: "new game")])
  h.assert_converged("game changed during outage", expected_count: 1)
end

check.call("reopening a screen recovers its pending move without planning it again") do
  h = NativeRoomHarness.new(users: %w[Alice Bob])
  h.start
  error = EltenLink::Error.new("rate_limits.exceeded")
  error.define_singleton_method(:retry_after) { 95 }
  h.view("Alice").fail_next_push = error
  begin
    h.write("Alice", [GameRoomGames::EventCommand.new(action: "tick", value: "same screen-independent operation")])
  rescue EltenLink::Error
  end
  original = h.view("Alice").instance_variable_get(:@push_attempts).last
  clock = [0.0]
  reopened = GameRoomSync::Controller.new(transport: h.transports["Alice"], table_id: h.table["__id"], clock: -> { clock[0] })
  assert(reopened.waiting? && reopened.next_reconcile_at == 95, "new screen lost pending state or Retry-After")
  clock[0] = 96
  assert(reopened.next_event.kind == :recovery, "new screen needs another move to trigger recovery")
  reopened.synchronize { h.events("Alice") }
  assert(h.view("Alice").instance_variable_get(:@push_attempts).last == original, "reopening recreated the move")
  h.assert_converged("reopened screen", expected_count: 1)
end

check.call("429 recovery obeys Retry-After despite new gaps and room/chat wake-ups") do
  h = NativeRoomHarness.new(users: %w[Alice Bob])
  h.start
  clock = [0.0]
  sync = controller_for(h, "Bob", clock)
  error = EltenLink::Error.new("rate_limits.exceeded")
  error.define_singleton_method(:retry_after) { 90 }
  h.broker.endpoint("Bob").report_error(error)
  assert(sync.next_event.nil? && sync.next_reconcile_at == 90, "native error did not schedule advertised delay")
  clock[0] = 10
  h.view("Bob").instance_variable_get(:@gap_callbacks).each { |cb| cb.call({}) }
  h.write("Alice", [GameRoomGames::EventCommand.new(action: "tick", value: "changed")])
  assert(sync.next_event.nil? && sync.next_reconcile_at == 90, "gap bypassed Retry-After")
  sync.synchronize(complete: false) { :cached_chat }
  assert(sync.next_reconcile_at == 90, "chat discarded the pending recovery")
  clock[0] = 90
  assert(sync.next_event.kind == :recovery, "retry never became due without keyboard activity")
  h.view("Bob").fail_next_read = error
  begin
    sync.synchronize { h.events("Bob") }
  rescue EltenLink::Error
  end
  assert(sync.next_reconcile_at == 180, "429 during recovery was not retained")
  clock[0] = 180
  assert(sync.next_event.kind == :recovery, "second retry was lost")
  sync.synchronize { h.events("Bob") }
  assert(!sync.recovery_pending?, "recovery did not finish")
  h.assert_converged("429 recovery", expected_count: 1)
end

class TwoHumanQuiz
  attr_reader :h, :contexts
  def initialize
    $recovery_now = 1000
    game = GameRoomGames::QuizParty.new
    @h = NativeRoomHarness.new(game: game, users: %w[Alice Bob], options: game.default_options.merge("answer_time" => 5))
    h.start
    @contexts = h.users.to_h do |user|
      [user, GameRoomGames::ActionContext.new(session_id: h.session["__id"], table_id: h.table["__id"], now: 1000,
        random_source: GameRoomRandom::SeededSource.new(33),
        hidden_submissions: HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new))]
    end
    auto("Alice")
    r = h.replay("Alice")
    h.submit("Alice", { "kind" => "question", "action" => "submit", "question_id" => game.send(:category_surface_id, r.state), "answer" => r.state[:choices].first }, context: contexts["Alice"])
    auto("Alice")
    h.users.each do |user|
      r = h.replay(user)
      h.submit(user, { "kind" => "question", "action" => "submit", "question_id" => game.send(:question_surface_id, r.state), "answer" => game.send(:correct_option_index, r.state).to_s }, context: contexts[user])
    end
    auto("Alice")
    h.users.each { |user| auto(user) }
    auto("Alice")
    $recovery_now = 1004
    contexts.each_value { |context| context.now = 1004 }
  end
  def auto(user); h.submit(user, context: contexts[user]); end
end

[:before, :after, :notification].each do |fault|
  check.call("two humans: Quiz Party leaves next-question waiting after #{fault} failure") do
    fixture = TwoHumanQuiz.new
    h = fixture.h
    old = h.replay("Alice")
    assert([:starting, :drawing].include?(old.state[:phase]), "quiz is not waiting for its next question")
    freeze_metadata(h)
    clock = [0.0]
    user = fault == :notification ? "Bob" : "Alice"
    sync = controller_for(h, user, clock)
    screen = screen_for(h, user, sync, context: fixture.contexts[user])
    h.as(user) do
      if fault == :notification
        fixture.auto("Alice")
        assert(h.replay("Bob").state == old.state, "reader metadata was not stale")
        # The host's existing control/recovery path delivers missed stack
        # messages. No new Game Room inactivity timer or polling is involved.
        h.broker.deliver(user: "Bob", duplicate: true)
        assert(sync.next_event.kind == :game_changed, "recovered native message did not wake the screen")
      else
        h.view(user).fail_next_push = fault
        assert(!screen.send(:perform_automatic_action, old), "uncertain transition reported success")
        first = h.view(user).instance_variable_get(:@push_attempts).last
        pushes = h.view(user).calls[:push]
        screen.send(:perform_automatic_action, old)
        assert(h.view(user).calls[:push] == pushes, "quiz generated another question before recovery")
        clock[0] = 31
        $recovery_now = 1035
        fixture.contexts.each_value { |context| context.now = $recovery_now }
        assert(sync.next_event.kind == :recovery, "human-only quiz has no recovery wake-up")
        reads = h.view(user).calls[:read]
        result = sync.synchronize { screen.send(:recover_game_update, h.repositories[user].events_revision(old.accepted_events)) }
        assert(result[3] == :refresh, "next-question screen did not wake up")
        assert(h.view(user).calls[:read] == reads + 1, "recovery repeated the same forced read")
        assert(h.view(user).instance_variable_get(:@push_attempts).last == first, "quiz recovery changed its question/seed/UUID")
      end
      h.broker.deliver(duplicate: true)
      h.assert_converged("quiz #{fault}")
      fresh = h.replay("Bob")
      assert(fresh.state[:phase] != old.state[:phase], "quiz still stuck preparing the next question")
      if fault == :before
        assert(fresh.state[:deadline] > $recovery_now, "retried question has an already expired answer time")
      elsif fault == :after
        # A previously committed question may have expired during the outage.
        # Existing rules close/score it, then progress normally without input.
        fixture.auto("Alice")
        fixture.auto("Alice")
        $recovery_now += 4
        fixture.contexts.each_value { |context| context.now = $recovery_now }
        fixture.auto("Alice")
        h.broker.deliver
        fresh = h.replay("Bob")
        assert(fresh.state[:phase] == :answering && fresh.state[:deadline] > $recovery_now,
          "expired committed question stranded the next automatic transition")
        h.assert_converged("quiz after expired committed question")
      end
    end
  end
end

check.call("human writes share uncertainty recovery and report a replay rejection") do
  h = NativeRoomHarness.new(users: %w[Alice Bob])
  h.start
  freeze_metadata(h)
  clock = [0.0]
  sync = controller_for(h, "Alice", clock)
  screen = screen_for(h, "Alice", sync)
  game = GameRoomGames::Base.new
  plans = 0
  game.define_singleton_method(:action_for) do |*_args, **_options|
    plans += 1
    [:ok, GameRoomGames::ActionPlan.new(events: [GameRoomGames::EventCommand.new(action: "tick", value: "human")])]
  end
  screen.instance_variable_set(:@game, game)
  replay = GameRoomGames::Replay.new(accepted_events: [], players: %w[Alice Bob])
  h.as("Alice") do
    h.view("Alice").fail_next_push = :before
    assert(!screen.send(:submit_action, replay), "failed human write reported success")
    assert(!screen.send(:submit_action, replay) && plans == 1, "human plan was recreated while uncertain")
    clock[0] = 31
    sync.next_event
    sync.synchronize { screen.send(:recover_game_update, [0, 0]) }
    # Transport confirmation is not game-rule acceptance. A stale human move
    # rejected by replay must use the existing choose-again message once.
    screen.send(:verify_pending_move, replay)
    alerts = screen.instance_variable_get(:@alerts)
    assert(alerts.last.include?("Please choose again"), "a recovered but stale action was silently lost")
    size = alerts.length
    screen.send(:verify_pending_move, replay)
    assert(alerts.length == size, "rejection was announced repeatedly")
  end
end

puts "Connection recovery tests passed: #{checks} cases"
