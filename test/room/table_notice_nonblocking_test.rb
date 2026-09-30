require_relative "../support/table_notice_presentation"

# A blocked disk write must not block receipt, enqueueing, sound or mapping.
entered, release = Queue.new, Queue.new
writes = []
writer = GameRoomTableWatch::ReceiptWriter.new do |value|
  writes << value
  if writes.length == 1
    entered << Thread.current
    release.pop
  end
end
writer.enqueue("resolved" => { "first" => 100 })
background = entered.pop
assert(background != Thread.current, "disk work is on the UI thread")
snapshot = { "resolved" => { "first" => 100, "last" => 300 } }
writer.enqueue("resolved" => { "first" => 100, "middle" => 200 })
writer.enqueue(snapshot)
snapshot["resolved"]["last"] = 999
assert(writes.length == 1, "concurrent writes while the first disk operation is blocked")
writer.close
release << true
assert(writer.instance_variable_get(:@thread).join(3), "writer did not drain on close")
assert(writes.length == 2 && writes.last["resolved"] == { "first" => 100, "last" => 300 }, "pending writes were not coalesced/isolated")
assert(!writer.enqueue("resolved" => {}), "closed writer accepted new work")

clock, attempts = 0, 0
writer = GameRoomTableWatch::ReceiptWriter.new(clock: -> { clock }) do |_value|
  attempts += 1
  raise IOError, "simulated disk failure"
end
writer.enqueue("resolved" => { "room" => 300 })
writer.instance_variable_get(:@thread).join(3)
writer.tick
assert(attempts == 1, "failure retried without backoff")
2.times do
  clock += 5
  writer.tick
  writer.instance_variable_get(:@thread).join(3)
end
clock += 100
writer.tick
assert(attempts == 3, "disk retry loop is not bounded")
writer.close

clock = 1000
persisted = []
receiver = GameRoomTableWatch::Receiver.new(user: "Alice", games: ["uno"], uuid: "uuid",
  clock: -> { clock }, persist: ->(data) { persisted << data })
build_notice = ->(id, room) { Notice2.new(id: id, app_uuid: "uuid", type: GameRoomTableWatch::TYPE, sender: "Bob",
  metadata: { "format" => 1, "game" => "uno", "table_id" => 12, "live_session_id" => room, "created_at" => 1000, "expires_at" => 1300 }) }
first = build_notice.call(1, "room1")
assert(receiver.receive(first) && persisted.empty?, "incoming announcement touched persistence")
assert(!receiver.receive(first) && !receiver.receive(build_notice.call(2, "room1")), "RAM delivery dedup failed")
assert(receiver.receive(build_notice.call(3, "room2")), "new table by the same sender was suppressed")
receiver.resolve("room3")
assert(!receiver.receive(build_notice.call(4, "room3")), "join before late delivery was forgotten")
receiver.resolve("room1")
assert(!receiver.visible?(first), "received announcement survived joining")
assert(persisted.last.keys == ["resolved"], "seen receipts are still written")
other = GameRoomTableWatch::Receiver.new(user: "Carol", games: ["uno"], uuid: "uuid", clock: -> { clock })
assert(other.receive(first), "one account suppressed another account")
clock = 1300
assert(!other.visible?(first), "expiration regressed")
assert(GameRoomTableWatch::Timing.samples.all? { |sample| sample.keys.sort == [:milliseconds, :stage] }, "timing buffer includes notification data")
puts "Table notice nonblocking receipts, coalescing, bounded retry, lifecycle and isolation: OK"
