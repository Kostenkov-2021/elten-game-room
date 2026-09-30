require "json"
require "tmpdir"
require "open3"
require_relative "../../lib/game_room_analytics_storage"
require_relative "../../lib/game_statistics_service"
require_relative "../../lib/game_room_presence_collector"

def assert(value, message)
  raise message unless value
  $checks = $checks.to_i + 1
end

now, triggers, calls = 0.0, [], []
job = GameRoomAnalyticsJob.new(clock: -> { now }, trigger: -> { triggers << now }) do |_token, upload|
  calls << upload
  :idle
end
job.request
20.times { job.request; job.tick }
assert(triggers == [0], "Queued requests were not coalesced")
job.run
100.times { now += 30; job.tick }
assert(calls == [true] && triggers.length == 1, "Idle statistics still poll periodically")

now, triggers, calls = 0.0, [], []
job = GameRoomAnalyticsJob.new(clock: -> { now }, trigger: -> { triggers << now }, persist_during_retry: true) do |_token, upload|
  calls << upload
  upload ? :retry : :waiting
end
job.request
job.run
[30, 60, 120, 300, 300].each do |delay|
  retry_at = now + delay
  now += 1
  job.request
  job.run
  assert(calls.last == false, "New work bypassed the network backoff")
  now = retry_at - 0.01
  count = triggers.length
  job.tick
  assert(triggers.length == count, "Upload retry fired early")
  now = retry_at
  job.tick
  job.run
  assert(calls.last == true, "Pending upload did not retry")
end
job.close
count = triggers.length
now += 1000
job.request
job.tick
job.run
assert(triggers.length == count, "Closed job restarted")

now, triggers, statuses = 0.0, [], [:active, :unchanged, :active, :idle]
job = GameRoomAnalyticsJob.new(clock: -> { now }, trigger: -> { triggers << now }, delay: 1, heartbeat: 120) { statuses.shift }
job.request
now = 0.5
job.request
now = 1
job.tick
job.run
assert(triggers == [1], "Presence debounce was postponed by repeated changes")
now = 30
job.request
now = 31
job.tick
job.run
now = 120.99
job.tick
assert(triggers.length == 2, "Presence heartbeat fired too early")
now = 121
job.tick
job.run
assert(triggers == [1, 31, 121], "An unchanged snapshot postponed presence renewal")
now = 122
job.request
now = 123
job.tick
job.run
now = 999
job.tick
assert(triggers.last == 123, "An empty presence still runs a heartbeat")

now, triggers, enabled = 0.0, [], true
job = nil
work = 0
job = GameRoomAnalyticsJob.new(clock: -> { now }, enabled: -> { enabled }, trigger: -> { triggers << now }) do |token, _|
  work += 1
  job.request if work == 1
  token.raise_if_cancelled!
  :idle
end
job.request
job.run
job.tick
job.run
assert(work == 2, "Notification arriving during flush was lost")
enabled = false
job.request
job.tick
job.run
assert(work == 2, "Disabled job performed work")
enabled = true
job.tick
job.run
assert(work == 3, "Re-enabling lost pending work")

[:not_due, :running, :inactive, false].each do |refusal|
  now, attempts, work = 0.0, 0, 0
  job = GameRoomAnalyticsJob.new(clock: -> { now }, trigger: -> { attempts += 1; attempts == 1 ? refusal : :queued }) do
    work += 1
    :idle
  end
  job.request
  now += 1
  job.tick
  job.run
  assert(attempts == 2 && work == 1, "Native scheduler refusal #{refusal.inspect} lost the wakeup")
end

Store = Struct.new(:writes, :failure, :during) do
  def write_batch(values, cancellation_token:)
    cancellation_token&.raise_if_cancelled!
    writes << values
    during&.call
    raise failure if failure
    values.length
  end
end

Dir.mktmpdir("game-room-analytics-") do |directory|
  resolutions = []
  program = Object.new
  program.define_singleton_method(:data_path) { resolutions << Thread.current; directory }
  program.define_singleton_method(:server_app_uuid) { "test-app" }
  storage = GameRoomAnalyticsStorage.new(program)
  store = Store.new([], nil, nil)
  now, triggers, user = 0.0, [], "Alice"
  job = nil
  queue = GameRoomStatistics::Queue.new(storage: storage, user: user)
  # More than one durable batch must upload even with no new UI events.
  123.times { |i| queue.push("fixture:#{i}", {"kind" => "visit", "day_key" => 20260000 + i}) }
  service = GameRoomStatistics::Service.new(program: program, storage: storage, user: user,
    current_user: -> { user }, store: store, trigger: -> { job.request }, clock: -> { 1_790_294_400 })
  job = GameRoomAnalyticsJob.new(clock: -> { now }, trigger: -> { triggers << now }, persist_during_retry: true) do |token, upload|
    service.flush(token, upload: upload)
    service.work_status
  end
  job.request
  3.times { job.tick; job.run; now += 1 }
  assert(store.writes.map(&:length) == [50, 50, 23] && queue.size == 0, "Startup durable backlog stopped after one batch")
  before = resolutions.length
  GameRoomPresence::Collector.reporter_key(storage: storage, user: user)
  10.times { queue.batch }
  assert(before == 1 && resolutions.length == 1, "Analytics repeatedly resolved the signed package data path")
  service.visit
  store.failure = IOError.new("reply lost after commit")
  job.run
  assert(queue.size == 1, "Uncertain write was acknowledged")
  # A different event is persisted during backoff, without another HTTP write.
  now += 1
  session = {"__statistics" => {"id" => "11111111-1111-4111-8111-111111111111", "mode" => "humans", "started_at" => 1_790_294_400}}
  service.started(session: session, game_id: "axel_pong")
  job.run
  assert(queue.size == 2 && store.writes.length == 4, "Backoff lost a new event or retried HTTP early")
  now += 30
  store.failure = nil
  store.during = -> { service.started(session: {"__statistics" => session["__statistics"].merge("id" => "22222222-2222-4222-8222-222222222222")}, game_id: "audio_ball") }
  job.tick
  job.run
  store.during = nil
  job.tick
  job.run
  assert(queue.size == 0 && store.writes.last.first["game"] == "audio_ball", "Event during actual upload was lost")
  # Account changes after server commit must not acknowledge the old account.
  service.started(session: {"__statistics" => session["__statistics"].merge("id" => "33333333-3333-4333-8333-333333333333")}, game_id: "uno")
  store.during = -> { user = "Bob" }
  job.run
  assert(queue.size == 1, "Account switch acknowledged old data")
  user = "Alice"
  store.during = nil
  service.close
  assert(!service.flush && queue.size == 1, "Closed service continued uploading")

  original = File.binread(File.join(directory, GameRoomStatistics::Queue::PATH))
  File.binwrite(File.join(directory, GameRoomStatistics::Queue::PATH), "{bad json")
  invalid = GameRoomStatistics::Service.new(program: program, storage: storage, user: "Alice", current_user: -> { "Alice" }, store: store)
  assert(!invalid.flush && invalid.work_status == :blocked, "Corrupt queue was treated as empty/retryable")
  assert(File.binread(File.join(directory, GameRoomStatistics::Queue::PATH)) == "{bad json", "Corrupt queue was overwritten")
  File.binwrite(File.join(directory, GameRoomStatistics::Queue::PATH), original)
  forbidden = begin; storage.read_json("../settings.json"); false; rescue ArgumentError; true; end
  assert(forbidden, "Adapter escaped its analytics-only file scope")
  raised = begin; storage.update_json(GameRoomStatistics::Queue::PATH) { raise "abort" }; false; rescue RuntimeError; true; end
  assert(raised && File.binread(File.join(directory, GameRoomStatistics::Queue::PATH)) == original, "Aborted update changed the durable queue")

  # Two independent handles share the lock file, not a replaceable JSON inode.
  copies = [storage, GameRoomAnalyticsStorage.new(program)]
  threads = copies.each_with_index.map do |copy, index|
    Thread.new { 20.times { |n| GameRoomStatistics::Queue.new(storage: copy, user: "Thread#{index}").push("#{n}", {"kind" => "visit"}) } }
  end
  threads.each(&:value)
  copies.each_with_index { |copy, i| assert(GameRoomStatistics::Queue.new(storage: copy, user: "Thread#{i}").size == 20, "Concurrent update was lost") }
end

now, calls = 0.0, []
room = Struct.new(:table, :members).new({"__statistics_room_id" => "11111111-1111-4111-8111-111111111111", "game" => "uno", "status" => "waiting"}, %w[Alice Bob])
target = Object.new
target.define_singleton_method(:publish) do |rooms, **_|
  calls << rooms
  raise IOError, "uncertain presence" if calls.length == 1
  true
end
collector = GameRoomPresence::Collector.new(user: "Alice", store: target, current_user: -> { "Alice" }, clock: -> { now }, synchronize_clock: -> {})
registration = collector.register { [room] }
assert(!collector.heartbeat, "Partial presence failure was accepted")
registration.close
assert(collector.heartbeat && calls.last == [], "Leaving after uncertain first publish did not clear its possible row")
puts "PASS analytics workers: #{$checks} assertions (idle, coalescing, retries, durable backlog, account/cancellation, strict atomic storage)"
