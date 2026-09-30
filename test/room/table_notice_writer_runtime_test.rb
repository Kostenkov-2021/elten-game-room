require_relative "../support/table_notice_presentation"

# Entering the captured app context can fail before the disk callback starts.
# This must release the busy flag and retain only a bounded retry.
module Programs
  def self.current_runtime; Thread.current[:notice_test_runtime]; end
  def self.with_runtime(runtime)
    raise IOError, "disposed runtime" if runtime == :disposed
    old = Thread.current[:notice_test_runtime]
    Thread.current[:notice_test_runtime] = runtime
    yield
  ensure
    Thread.current[:notice_test_runtime] = old
  end
end
clock = 0
writer = GameRoomTableWatch::ReceiptWriter.new(runtime: :disposed, clock: -> { clock }) { raise "must not reach storage" }
writer.enqueue("resolved" => { "room" => 500 })
3.times do |attempt|
  assert(writer.instance_variable_get(:@thread).join(3), "disposed context left a running worker")
  assert(!writer.instance_variable_get(:@running), "disposed context left writer busy")
  clock += 5
  writer.tick
end
assert(writer.instance_variable_get(:@failures) == 3 && writer.instance_variable_get(:@pending), "context failures lost retry state")
writer.close

# Real runtime adapter with host-style in-place update_json. An old writer
# finishing after an account switch must still update only its captured user.
class ReceiptRuntimeFixture
  extend GameRoomTableWatchRuntime
  GAME_REGISTRY = Struct.new(:ids).new(["uno"])
  def self.server_app_uuid; "uuid"; end
end
account = "Alice"
Session.define_singleton_method(:name) { account }
store = { "untouched" => { "resolved" => { "old" => Time.now.to_f + 1000 } } }
storage_lock, entered, release = Mutex.new, Queue.new, Queue.new
writes = []
ReceiptRuntimeFixture.define_singleton_method(:read_json) { |_, default:| Marshal.load(Marshal.dump(store)) }
ReceiptRuntimeFixture.define_singleton_method(:update_json) do |_, default:, &block|
  context = Programs.current_runtime
  if context == :alice_runtime
    entered << true
    release.pop
  end
  storage_lock.synchronize { block.call(store) }
  writes << context
end
Thread.current[:notice_test_runtime] = :alice_runtime
first = ReceiptRuntimeFixture.table_watch_receiver
first.resolve("alice-room")
old_writer = ReceiptRuntimeFixture.instance_variable_get(:@table_watch_receipt_writer)
entered.pop
account = "Bob"
Thread.current[:notice_test_runtime] = :bob_runtime
second = ReceiptRuntimeFixture.table_watch_receiver
second.resolve("bob-room")
new_writer = ReceiptRuntimeFixture.instance_variable_get(:@table_watch_receipt_writer)
assert(new_writer.instance_variable_get(:@thread).join(3), "new account write stalled")
release << true
assert(old_writer.instance_variable_get(:@thread).join(3), "old account write stalled")
assert(writes.sort == [:alice_runtime, :bob_runtime], "worker did not retain app runtime")
assert(store.fetch("alice").fetch("resolved").keys == ["alice-room"], "old writer used new account")
assert(store.fetch("bob").fetch("resolved").keys == ["bob-room"], "old writer overwrote new account")
assert(store.key?("untouched"), "writing receipt removed another account")
assert(first.user == "Alice" && second.user == "Bob", "account receiver reused")

# Late snapshots merge with newer durable joins instead of overwriting them.
store["bob"]["resolved"]["other-join"] = Time.now.to_f + 1000
store["bob"]["resolved"]["bob-room"] = later = Time.now.to_f + 2000
second.resolve("next-room")
assert(new_writer.instance_variable_get(:@thread).join(3), "merged write stalled")
assert(store["bob"]["resolved"].keys.sort == %w[bob-room next-room other-join], "stale snapshot erased a join")
assert(store["bob"]["resolved"]["bob-room"] == later, "stale snapshot shortened expiry")
ReceiptRuntimeFixture.table_watch_stop
assert(new_writer.enqueue("resolved" => { "after-restart" => Time.now.to_f + 300 }), "extension restart closed retained writer")
assert(new_writer.instance_variable_get(:@thread).join(3), "restart write stalled")
new_writer.close
Thread.current[:notice_test_runtime] = nil
puts "PASS table notice writer: captured runtime/account, late merges, failed context and extension restart"
