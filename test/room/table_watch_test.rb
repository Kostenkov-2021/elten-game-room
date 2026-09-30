require_relative "../support/table_watch"

clock_source = Struct.new(:now, :online, :synchronized) do
  def server_available?; online; end
  def synchronized?; synchronized; end
end.new(1000.0, true, true)
clock = GameRoomTableWatch::Clock.new(source: clock_source)
assert(clock.call == 1000 && clock.ready?, "notice clock did not use the shared clock")
clock_source.now = 1301
assert(clock.call == 1301, "notice clock cached the shared clock")
clock_source.synchronized = false
assert(!clock.ready?, "account change/cold host clock remained ready")
clock_source.now, clock_source.synchronized = 1320, true
assert(clock.call == 1320 && clock.ready?, "fresh native sample was not adopted")

table = WatchTable.new
repository = GameRoomTableWatch::Preferences.new(table, games: %w[uno rummy])
assert(repository.load("Alice") == [] && table.writes.empty?, "first read wrote defaults")
repository.save("Alice", %w[uno uno fake])
assert(repository.load("Alice") == ["uno"], "selection normalization")
before = table.writes.size
repository.save("Alice", ["uno"])
assert(table.writes.size == before, "unchanged save wrote a record")
table.insert("username" => "Alice", "format" => 1, "games" => '["rummy"]')
assert(repository.load("Alice") == ["uno"], "duplicate winner is not deterministic")
table.user = "Mallory"
table.insert("username" => "Alice", "format" => 1, "games" => '["rummy"]')
table.user = "Alice"
repository.save("Alice", ["rummy"])
assert(table.rows.count { |row| row["__insertion_user"] == "Alice" } == 1, "own duplicates remain")
assert(table.queries.all? { |query| query[:columns] == %w[__id __insertion_user username format games] },
  'Preference projection omitted ownership or fetched unused fields')
assert(table.rows.count { |row| row["__insertion_user"] == "Mallory" } == 1, "foreign row removed")
assert(repository.recipients("rummy", online: %w[ALICE Alice Mallory], sender: "Bob") == ["Alice"], "recipients forged or duplicated")
assert(repository.recipients("rummy", online: ["Alice"], sender: "alice") == [], "sender notified itself")

now = 1000
session_id = "12345678-1234-1234-1234-123456789abc"
meta = { "format" => 1, "game" => "uno", "table_id" => 12, "live_session_id" => session_id,
  "created_at" => now, "expires_at" => now + 300 }
notice = WatchNotice.new(id: 1, app_uuid: "uuid", type: GameRoomTableWatch::TYPE, sender: "Bob", metadata: meta)
stored = {}
receiver = GameRoomTableWatch::Receiver.new(user: "Alice", uuid: "uuid", games: %w[uno rummy],
  clock: -> { now }, persist: ->(data) { stored = Marshal.load(Marshal.dump(data)) })
assert(receiver.visible?(notice) && receiver.receive(notice), "fresh notice missing before startup preference read")
assert(!receiver.receive(notice) && receiver.visible?(notice), "same notice alerted twice or vanished")
duplicate = notice.dup; duplicate.id = 2
assert(!receiver.visible?(duplicate), "duplicate leaves an empty list row")
restarted = GameRoomTableWatch::Receiver.new(user: "Alice", uuid: "uuid", games: %w[uno rummy], stored: stored, clock: -> { now })
assert(stored.empty? && !restarted.received?(notice), "receiving unnecessarily persisted seen IDs; startup delivery belongs to the host")
receiver.games = ["rummy"]
assert(!receiver.visible?(notice), "disabled game passed receiver filter")
receiver.games = ["uno"]
now = 1300
assert(!receiver.visible?(notice), "expired announcement remains visible")
now = 1000
receiver.resolve(session_id)
assert(!receiver.visible?(notice), "manual join did not resolve announcement")
restarted = GameRoomTableWatch::Receiver.new(user: "Alice", uuid: "uuid", games: %w[uno rummy], stored: stored, clock: -> { now })
assert(!restarted.visible?(notice), "restart lost resolved/joined table suppression")
bad = notice.dup; bad.metadata = meta.merge("live_session_id" => "https://evil.invalid")
assert(receiver.data(bad) == nil, "untrusted target accepted")
bad.metadata = meta.merge("expires_at" => 999999)
assert(receiver.data(bad) == nil, "unbounded expiration accepted")

worker = WatchWorker.new
sent, online_calls, loads = [], 0, 0
fake_repository = Object.new
fake_repository.define_singleton_method(:recipients) { |*_, **_| loads += 1; %w[Bob Carol] }
sender = GameRoomTableWatch::Sender.new(user: "Alice", repository: fake_repository, worker: worker,
  online: -> { online_calls += 1; %w[Bob Carol] }, clock: -> { now }, current_user: -> { "Alice" },
  send_notice: ->(name, metadata, expires) { sent << [name, metadata, expires] })
row = { "owner" => "Alice", "status" => "waiting", "game" => "uno", "__id" => 12, "__live_session_id" => session_id }
assert(!sender.enqueue(row.merge("private" => true)), "private room announced")
assert(!sender.enqueue(row.merge("resume_save_id" => "save")), "resumed room announced")
assert(sender.enqueue(row) && !sender.enqueue(row), "created event not deduplicated")
sender.tick; worker.finish; sender.tick
assert(loads == 1 && online_calls == 1, "recipient discovery did not batch online")
worker.finish; sender.tick
assert(sent.size == 1 && !worker.busy?, "rate pacing ignored")
now += 0.5
sender.tick; worker.finish(Limited.new("HTTP 429")); sender.tick
now += 59
sender.tick
assert(!worker.busy?, "429 was immediately retried")
now += 1
sender.tick; worker.finish; sender.tick
assert(sent.map(&:first) == %w[Bob Carol], "explicit rejected send was not retried once")
assert(sent.last.last < sent.first.last, "expiry reset for each recipient")
now = 2000
new_row = row.merge("__live_session_id" => "12345678-1234-1234-1234-123456789abd")
sender.enqueue(new_row); sender.tick; worker.finish; sender.tick
worker.finish(Uncertain.new("response lost")); sender.tick
now += 20
sender.tick
sender.cancel(new_row["__live_session_id"])
worker.finish
sender.tick
assert(sent.size == 2, "uncertain write retried or cancelled job sent")
puts "Table subscriptions, author checks, receipts, expiry and paced notifications passed"

[:partial, :lost].each do |failure|
  duplicates = WatchTable.new
  preferences = GameRoomTableWatch::Preferences.new(duplicates, games: ['uno'])
  206.times { duplicates.insert('username' => 'Alice', 'format' => 1, 'games' => '["uno"]') }
  duplicates.user = 'Mallory'
  foreign = duplicates.insert('username' => 'Alice', 'format' => 1, 'games' => '["uno"]')
  duplicates.user = 'Alice'
  sizes, first = [], true
  original_delete = duplicates.method(:delete_many)
  duplicates.define_singleton_method(:delete_many) do |ids|
    sizes << ids.length
    if first
      first = false
      count = original_delete.call(ids.take(3))
      raise IOError, 'delete response lost' if failure == :lost
      count
    else
      original_delete.call(ids)
    end
  end
  preferences.recipients('uno', online: ['Alice'], sender: 'Bob')
  begin
    preferences.save('Alice', [])
    raise 'Partial/uncertain duplicate removal succeeded'
  rescue IOError
  end
  assert(preferences.recipients('uno', online: ['Alice'], sender: 'Bob').empty?, 'Uncertain deletion left stale preferences cache')
  assert(preferences.save('Alice', []) == [], 'Retry did not reread remaining duplicates')
  assert(sizes == [100, 100, 100, 2], 'Duplicate deletes were not bounded/reconciled')
  assert(duplicates.rows.length == 2 && duplicates.rows.include?(foreign), 'Removed canonical or foreign preference row')
end
puts 'PASS bulk preference deletion: owner verification, partial/lost replies, cache invalidation, bounded retry'

# If the host invalidates time while an operation completes, leave its outcome
# pending until a new sample arrives. Do not lose a send/load acknowledgement.
ready = false
clock = Struct.new(:now, :available) do
  def call; raise 'Read cold clock' unless available.call; now; end
  def ready?; available.call; end
end.new(3000.0, -> { ready })
paused_worker = WatchWorker.new
paused_sender = GameRoomTableWatch::Sender.new(user: 'Alice', repository: fake_repository, worker: paused_worker,
  online: -> { %w[Bob Carol] }, clock: clock, current_user: -> { 'Alice' }, send_notice: ->(*) {})
ready = true
assert(paused_sender.enqueue(row.merge('__live_session_id' => 'cold-sender')), 'Could not enqueue fixture')
paused_sender.tick
paused_worker.finish
ready = false
paused_sender.tick
assert(paused_worker.busy?, 'Cold clock consumed and lost a pending result')
ready = true
paused_sender.tick
assert(paused_worker.busy?, 'Recovered clock did not schedule the loaded recipients')
paused_sender.close
puts 'PASS native clock invalidation during pending notification work'
