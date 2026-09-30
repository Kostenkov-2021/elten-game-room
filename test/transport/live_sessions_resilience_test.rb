require_relative "../support/native_room_harness"
require_relative "../support/log"

seed = Integer(ARGV[0] || ENV.fetch("GAME_ROOM_RESILIENCE_SEED", "20260910"), 10)
batches = Integer(ARGV[1] || ENV.fetch("GAME_ROOM_RESILIENCE_BATCHES", "400"), 10)
raise ArgumentError, "positive batch count required" unless batches.positive?
random = Random.new(seed)
h = NativeRoomHarness.new
h.start
h.broker.automatic_delivery = false
expected = 0
restarts = 0
faults = 0
recovery_clock = 0.0
controllers = h.users.to_h do |user|
  [user, GameRoomSync::Controller.new(transport: h.transports[user], table_id: h.table["__id"], clock: -> { recovery_clock })]
end

settle = lambda do |stage|
  h.broker.deliver(duplicate: true)
  h.users.each do |user|
    controller = controllers[user]
    12.times do
      event = controller.next_event
      break if event == nil
      controller.synchronize do
        current = h.repositories[user].session_for_table(h.table)
        controller.update_session(current["__id"])
        h.repositories[user].snapshot_for(current)
      end
    end
    assert(controller.session_id == h.session["__id"], "#{stage}: #{user} missed the game-start/gap notification")
  end
  h.assert_converged(stage, expected_count: expected)
end
settle.call("initial native session")

batches.times do |batch|
  # Independently delay each reader by several virtual batches. No sleep,
  # Signals backend, or app-table storage is involved.
  actors = h.users.sample(random.rand(1..4), random: random)
  sequence = expected + 1
  actors.each do |actor|
    fault = batch % 31 == 0 ? :after : (batch % 37 == 0 ? :before : nil)
    h.view(actor).fail_next_push = fault
    begin
      h.write(actor, [GameRoomGames::EventCommand.new(action: "tick", value: "#{batch}:#{actor}")], sequence: sequence)
      expected += 1
    rescue EltenAPI::LiveSessions::TimeoutError => error
      faults += 1
      controller = controllers[actor]
      controller.failed!(error)
      recovery_clock += GameRoomSync::ERROR_BACKOFF + 1
      assert(controller.next_event.kind == :recovery, "uncertain move lost its recovery")
      # Resolve through the common recovery path. If absent, retry the SAME
      # operation identity instead of silently dropping a pre-commit failure.
      h.as(actor) { controller.synchronize { h.events(actor) } }
      expected += 1
    end
    h.broker.deliver(user: h.users.sample(random: random), limit: random.rand(1..5), duplicate: random.rand(2).zero?)
  end
  if batch % 40 == 39
    settle.call("before restart #{batch}")
    # Dave is deliberately left behind while an entire game is replaced.
    h.start
    expected = 0
    restarts += 1
    assert(h.core.entries.map { |entry| entry["packet"]["kind"] } == %w[room_state game_started],
      "starting a new game retained earlier server history")
    settle.call("restart #{batch}")
  end
  settle.call("batch #{batch}") if batch % 13 == 12
end
settle.call("final state")
assert(faults > 0, "resilience test did not inject a lost acknowledgement")

# An owner acknowledgement for sequence N must not hide a missing remote N-1.
gap = NativeRoomHarness.new
gap.start
gap.broker.automatic_delivery = false
gap.write("Bob", [GameRoomGames::EventCommand.new(action: "tick", value: "earlier remote")], sequence: 1)
gap.write("Alice", [GameRoomGames::EventCommand.new(action: "tick", value: "later own ack")], sequence: 1)
gap.assert_converged("local acknowledgement overtaking delivery", expected_count: 2)

# A failed read cannot be silently presented as an up-to-date, partial game.
gap.write("Bob", [GameRoomGames::EventCommand.new(action: "tick", value: "unread")], sequence: 3)
gap.view("Dave").fail_next_read = EltenAPI::LiveSessions::TimeoutError.new("read timeout")
clock = 0.0
read_controller = GameRoomSync::Controller.new(transport: gap.transports["Dave"], table_id: gap.table["__id"], clock: -> { clock })
begin
  read_controller.synchronize { gap.events("Dave") }
  raise "partial state was reported as a successful read"
rescue EltenAPI::LiveSessions::TimeoutError
end
clock = GameRoomSync::ERROR_BACKOFF + 1
# Drain initial room events as well as the scheduled retry.
events = 5.times.filter_map { read_controller.next_event }
assert(events.any? { |event| event.kind == :recovery }, "failed native read did not schedule recovery")
read_controller.synchronize { gap.events("Dave") }
gap.assert_converged("failed native read followed by recovery", expected_count: 3)

# Stack reads use multiple pages; a fresh attachment cannot inherit the old
# client's local history or lose events at page boundaries.
paged = NativeRoomHarness.new(users: %w[Alice Bob])
paged.start
paged.broker.automatic_delivery = false
260.times do |i|
  paged.write("Alice", [GameRoomGames::EventCommand.new(action: "tick", value: i.to_s)], sequence: i + 1)
end
paged.add_client("Carol")
assert(paged.join("Carol"), "fresh client could not join")
assert(paged.events("Carol").length == 260 && paged.view("Carol").calls[:read] >= 3, "stack pagination lost records")

# Both failure windows of a cleanup are harmless to the already stored new
# game. A subsequent restart can retry cleanup, without restarting that game.
[:before, :after].each do |phase|
  h.view("Alice").fail_next_trim = phase
  current = h.start
  assert(current && h.repositories["Bob"].session_for_table(h.table)["__id"] == current["__id"],
    "#{phase}-trim timeout invalidated a confirmed start")
end

puts "Native LiveSessions resilience passed: seed=#{seed} batches=#{batches} restarts=#{restarts} uncertain_writes=#{faults}"
