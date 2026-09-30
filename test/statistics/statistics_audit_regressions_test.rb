require "json"
require "monitor"
require_relative "../support/statistics_tables"
require_relative "../../lib/game_statistics_service"
require_relative "../../lib/game_room_presence_collector"

def check(value, message)
  raise message unless value
  $checks = $checks.to_i + 1
end

class AuditStorage
  attr_reader :data, :reads, :writes
  attr_accessor :failure
  def initialize
    @data, @reads, @writes, @lock = {}, 0, 0, Monitor.new
  end
  def read_json(path, default:)
    @lock.synchronize do
      @reads += 1
      Marshal.load(Marshal.dump(@data.fetch(path, default)))
    end
  end
  def update_json(path, default:)
    @lock.synchronize do
      @writes += 1
      raise failure if failure
      copy = Marshal.load(Marshal.dump(@data.fetch(path, default)))
      yield copy
      @data[path] = copy
    end
  end
end

def payload(number, kind: "started", day: 20260929)
  {"kind" => kind, "game" => "axel_pong", "mode" => "humans", "day_key" => day,
    "match" => format("00000000-0000-4000-8000-%012d", number)}
end

def store_fixture(**options)
  api = StatisticsMemoryApi.new
  store = GameRoomStatistics::Store.new(app_uuid: "audit", user: "Alice", current_user: -> { "Alice" },
    client: Object.new, api: api, **options)
  [store, api, api.tables.fetch(GameRoomStatistics::Schema::EVENTS)]
end

# Bulk writes reduce requests without changing canonical event identities.
store, api, table = store_fixture
batch = (1..50).map { |i| payload(i) }
check(store.write_batch(batch) == 50, "Whole fast batch not confirmed")
requests = api.calls.length + table.queries.length + table.bulk_calls.length
check(requests == 5 && table.bulk_calls.map(&:length) == [25, 25], "New batch was not batched: #{requests}")
before = requests
check(store.write_batch(batch) == 50 && table.rows.length == 50, "Retry inserted duplicate events")
requests = api.calls.length + table.queries.length + table.bulk_calls.length - before
check(requests == 5, "Existing batch lookup was not batched: #{requests}")
check(store.write_batch([payload(1, day: 20260930), payload(1)]) == 2 && table.rows.length == 50,
  "Cross-day retry or repeated payload lost original identity")
begin
  store.write_batch([payload(1).merge("game" => "uno")])
  raise "Conflicting game was accepted"
rescue GameRoomStatistics::UnsafeReport
  check(table.rows.length == 50, "Conflicting record was inserted")
end

# A finite time slice acknowledges a prefix; queued remainder keeps progressing.
now = 0.0
store, api, table = store_fixture(monotonic: -> { now })
table.after_bulk = ->(_rows) { now += 1.1 }
storage = AuditStorage.new
queue = GameRoomStatistics::Queue.new(storage: storage, user: "Alice")
queue.push_many(batch.map.with_index { |item, i| ["entry:#{i}", item] })
service = GameRoomStatistics::Service.new(program: storage, storage: storage, queue: queue, store: store,
  user: "Alice", current_user: -> { "Alice" }, clock: -> { Time.utc(2026, 9, 29).to_i })
before_reads = storage.reads
check(service.flush && service.work_status == :more, "Slow batch did not yield")
check(storage.reads == before_reads + 1, "Flush reread the entire queue after acknowledgement")
check(queue.size == 25 && table.rows.length == 25, "Unconfirmed suffix was acknowledged")
check(service.flush && service.work_status == :idle && queue.size == 0 && table.rows.length == 50,
  "Yielded suffix did not finish")

# Prefix committed before a broken reply remains queued and retries idempotently.
[1, 25, 30, 50].each do |fail_after|
  store, _api, table = store_fixture
  table.after_insert = lambda do |_row|
    raise IOError, "lost bulk reply" if table.rows.length == fail_after
  end
  begin
    store.write_batch(batch)
    raise "Broken reply unexpectedly confirmed"
  rescue IOError
    check(table.rows.length == fail_after, "Partial-commit fixture failed")
  end
  table.after_insert = nil
  check(store.write_batch(batch) == 50 && table.rows.length == 50 && table.rows.map { |row| row["event_key"] }.uniq.length == 50,
    "Partial commit duplicated/lost events at #{fail_after}")
end

[:missing, :duplicate, :bad_id, :changed_value, :reordered].each do |kind|
  store, _api, table = store_fixture
  table.after_bulk = lambda do |rows|
    case kind
    when :missing then rows.pop
    when :duplicate then rows[1] = rows[0]
    when :bad_id then rows[0]["__id"] = 0
    when :changed_value then rows[0]["game"] = "uno"
    when :reordered then rows.reverse!
    end
  end
  begin
    confirmed = store.write_batch(batch.first(2))
    check(kind == :reordered && confirmed == 2, "Malformed bulk reply accepted: #{kind}")
  rescue GameRoomStatistics::Unavailable
    check(kind != :reordered, "Order-independent confirmation rejected")
  end
end

# Neither cancellation nor an account switch after commit acknowledges the batch.
[:cancel, :account].each do |mode|
  user, cancelled = "Alice", false
  token = Object.new
  token.define_singleton_method(:raise_if_cancelled!) { raise GameRoomAnalyticsJob::Cancelled if cancelled }
  api = StatisticsMemoryApi.new
  table = api.tables.fetch(GameRoomStatistics::Schema::EVENTS)
  store = GameRoomStatistics::Store.new(app_uuid: "audit", user: "Alice", current_user: -> { user }, client: Object.new, api: api)
  storage = AuditStorage.new
  queue = GameRoomStatistics::Queue.new(storage: storage, user: "Alice")
  queue.push_many(batch.first(2).map.with_index { |item, i| [i.to_s, item] })
  service = GameRoomStatistics::Service.new(program: storage, queue: queue, store: store, user: "Alice", current_user: -> { user })
  table.after_bulk = ->(_rows) { mode == :cancel ? cancelled = true : user = "Bob" }
  check(!service.flush(token) && queue.size == 2 && table.rows.length == 2, "#{mode} acknowledged the wrong context")
  user, cancelled, table.after_bulk = "Alice", false, nil
  check(service.flush(token) && queue.size == 0 && table.rows.length == 2, "#{mode} recovery duplicated data")
end

# Cold visit: no HTTP/storage on UI; use server day of entry even across midnight.
ready, mono, epoch, syncs = false, 0.0, Time.utc(2026, 10, 8).to_i, 0
storage = AuditStorage.new
store, api, table = store_fixture
queue = GameRoomStatistics::Queue.new(storage: storage, user: "Alice")
synchronize = lambda do
  syncs += 1
  raise IOError, "server temporarily offline" if syncs == 1
  ready = true
  epoch = Time.utc(2026, 9, 29, 22, 0, 1).to_i # Warsaw 00:00:01, ten seconds after entry.
end
service = GameRoomStatistics::Service.new(program: storage, queue: queue, store: store, user: "Alice",
  current_user: -> { "Alice" }, clock: -> { epoch }, clock_ready: -> { ready }, synchronize_clock: synchronize, monotonic: -> { mono })
check(service.visit && syncs == 0 && storage.reads == 0 && storage.writes == 0, "Cold visit did I/O on UI")
mono = 10.0
check(!service.flush && service.work_status == :retry && table.rows.empty?, "Failed clock wrote a wrong date")
check(service.flush(upload: false) && syncs == 1 && service.work_status == :waiting, "Backoff retried clock HTTP")
check(service.flush && table.rows.length == 1 && table.rows[0]["day_key"] == 20260929, "Cold visit moved to upload day or OS day")
check(service.visit && service.flush && table.rows.length == 2 && table.rows[1]["day_key"] == 20260930,
  "Visit after midnight did not keep its own day")
check(!service.visit && service.flush && table.rows.length == 2, "Repeated visit on the same day was duplicated")

# A new event may be persisted during Retry-After, never uploaded prematurely.
now, triggers, calls = 0.0, [], []
error = IOError.new("rate limited")
error.define_singleton_method(:retry_after) { 120 }
job = GameRoomAnalyticsJob.new(clock: -> { now }, trigger: -> { triggers << now }, persist_during_retry: true,
  last_error: -> { error }) { |_token, upload| calls << upload; upload ? :retry : :waiting }
job.request
job.run
now = 10
job.request
job.run
check(calls == [true, false], "New event bypassed server backoff")
[30, 60, 119.999].each { |time| now = time; job.tick; job.run }
check(calls == [true, false], "Retried before server's Retry-After")
now = 120
job.tick
job.run
check(calls == [true, false, true], "Retry did not fire at server deadline")

# Uncertain presence changed back to the last confirmed state still needs write.
Snapshot = Struct.new(:table, :members)
room = Snapshot.new({"__statistics_room_id" => "11111111-1111-4111-8111-111111111111", "game" => "uno", "status" => "waiting"}, %w[Alice Bob])
server_rows, lose_reply, publishes, now = [], false, [], 0.0
target = Object.new
target.define_singleton_method(:publish) do |rooms, **_options|
  publishes << rooms
  server_rows = rooms
  raise IOError, "lost presence confirmation" if lose_reply
  true
end
collector = GameRoomPresence::Collector.new(user: "Alice", current_user: -> { "Alice" }, store: target,
  clock: -> { now }, synchronize_clock: -> {})
registration = collector.register { [room] }
check(collector.heartbeat && server_rows.first["people"] == 2, "Initial presence failed")
room.members = %w[Alice Bob Carol]
lose_reply, now = true, 10
check(!collector.heartbeat && server_rows.first["people"] == 3, "Uncertain presence fixture failed")
room.members, lose_reply, now = %w[Alice Bob], false, 40
check(collector.heartbeat && server_rows.first["people"] == 2 && publishes.length == 3,
  "Same-as-confirmed presence skipped uncertain correction")
now = 50
check(collector.heartbeat && collector.work_status == :unchanged && publishes.length == 3, "Unchanged state needlessly republished")
registration.close
lose_reply = true
check(!collector.heartbeat && server_rows.empty?, "Uncertain deletion fixture failed")
collector.register { [room] }
lose_reply = false
check(collector.heartbeat && server_rows.first["people"] == 2, "Rejoin after uncertain deletion was skipped")

# Valid JSON with invalid structure is permanent; ordinary I/O is retryable.
[[], {"version" => 2, "accounts" => {}}, {"version" => 1, "accounts" => {"alice" => "broken"}}].each do |bad|
  storage = AuditStorage.new
  storage.data["room-presence-client.json"] = bad
  factory = -> { GameRoomPresence::Collector.reporter_key(storage: storage, user: "Alice"); target }
  collector = GameRoomPresence::Collector.new(user: "Alice", current_user: -> { "Alice" }, store_factory: factory, synchronize_clock: -> {})
  collector.register { [room] }
  check(!collector.heartbeat && collector.work_status == :blocked && collector.last_error.is_a?(GameRoomPresence::InvalidClientState),
    "Corrupt identity treated as network outage")
  check(storage.data["room-presence-client.json"] == bad, "Corrupt identity overwritten")
end

storage = AuditStorage.new
storage.failure = IOError.new("temporarily unavailable disk")
collector = GameRoomPresence::Collector.new(user: "Alice", current_user: -> { "Alice" }, synchronize_clock: -> {},
  store_factory: -> { GameRoomPresence::Collector.reporter_key(storage: storage, user: "Alice"); target })
collector.register { [room] }
check(!collector.heartbeat && collector.work_status == :retry, "Temporary disk failure permanently blocked presence")
storage.failure = nil
check(collector.heartbeat && collector.work_status == :active, "Transient identity I/O did not recover")

# Read snapshots are short, bounded and explicitly refreshed, not schema cached.
now = 0.0
store, api, table = store_fixture(monotonic: -> { now })
store.write_batch(batch)
period = GameRoomStatistics::Periods.options(today: Date.new(2026, 9, 29), years: []).last
first = store.report(period, reuse_snapshot: true)
before = table.queries.length
second = store.report(period, reuse_snapshot: true)
check(first == second && table.queries.length - before == 2, "Report repeated metadata/canonical queries")
before = table.queries.length
store.years(today: Date.new(2026, 9, 29))
check(table.queries.length - before == 2, "Explicit refresh did not refresh metadata")
before = table.queries.length
store.report(period, reuse_snapshot: true)
check(table.queries.length - before == 4, "Fresh metadata was not shared with report")
now = 16
before = table.queries.length
store.report(period, reuse_snapshot: true)
check(table.queries.length - before == 6, "Expired snapshot was reused")
store.write_batch([payload(99)])
check(store.report(period, reuse_snapshot: true)["started"] == 51, "Write did not invalidate the read snapshot")
api.schema_value["data"]["server"]["tables"][GameRoomStatistics::Schema::EVENTS]["filter_for"] = "creator"
begin
  store.report(period, reuse_snapshot: true)
  raise "Cached snapshot bypassed privacy schema validation"
rescue GameRoomStatistics::UnsafeReport
  check(true, "Unsafe schema rejected")
end

# Large reports share canonical identities across periods; no unbounded cache.
store, api, table = store_fixture
2050.times do |i|
  item = payload(i + 1)
  table.rows << {"__id" => i + 1, "event_key" => Digest::SHA256.hexdigest(["started", item["match"]].join("\0")),
    "kind" => "started", "game" => "axel_pong", "day_key" => 20260929, "mode" => "humans", "person" => 0}
end
check(store.report(period, reuse_snapshot: true)["started"] == 2050, "Large report count changed")
first_requests = api.calls.length + table.queries.length
check(first_requests == 49, "First large canonical read has unexpected cost: #{first_requests}")
check(store.report(period, reuse_snapshot: true)["started"] == 2050, "Repeated large report changed")
repeated_requests = api.calls.length + table.queries.length - first_requests
check(repeated_requests == 5, "Repeated large report did not reuse canonical metadata: #{repeated_requests}")
store.instance_variable_get(:@read_snapshot)[:canonical].replace((1..4096).to_h { |i| ["old:#{i}", {}.freeze] })
check(store.report(period, reuse_snapshot: true)["started"] == 2050 &&
  store.instance_variable_get(:@read_snapshot)[:canonical].length == 4096, "Canonical cache is unbounded or changed results")

puts "PASS statistics audit regressions: #{$checks} assertions; bulk 50 new=5 requests, repeated=5; partial commits, yielding, context, clock, backoff, presence, read cache"
