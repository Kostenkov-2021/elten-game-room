require_relative '../support/native_live_sessions'

# A native page describes one snapshot, not entries from before an append
# followed by through/has_more from after it. Force that interleaving without
# depending on sleeps or scheduling speed. This is an offline fixture test.
class StackSnapshotMutex
  def initialize(signals)
    @mutex, @signals = Mutex.new, signals
  end

  def synchronize
    unless @mutex.try_lock
      @signals << :writer_waiting
      @mutex.lock
    end
    begin
      yield
    ensure
      @mutex.unlock
    end
  end
end

broker = NativeLiveSessionsBroker.new
broker.automatic_delivery = false
endpoint = broker.endpoint('Alice')
session = endpoint.create(metadata: {}, participant_metadata: {}, capacity: 8,
  visibility: :public, discovery_metadata: {}, stack_entries: 4096, stack_entry_bytes: 16_384)
core = broker.cores.fetch(session.id)
selected, release, signals, start_read = Queue.new, Queue.new, Queue.new, Queue.new
core.mutex = StackSnapshotMutex.new(signals)
reader = writer = nil
select_entries = core.entries.method(:select)
core.entries.define_singleton_method(:select) do |&condition|
  result = select_entries.call(&condition)
  if Thread.current.equal?(reader)
    selected << true
    release.pop
  end
  result
end
begin
  reader = Thread.new { start_read.pop; session.stack_read(after: 0, limit: 128) }
  reader.report_on_exception = false
  start_read << true
  selected.pop
  writer = Thread.new do
    session.stack_push({'sample' => 'concurrent append'}, message_id: SecureRandom.uuid)
  ensure
    signals << :writer_finished
  end
  writer.report_on_exception = false
  # The old fixture completes the append; the corrected one waits on the
  # read snapshot's lock. Both paths release through the same explicit gate.
  signal = signals.pop
  assert(%i[writer_waiting writer_finished].include?(signal), 'Unknown synchronization signal')
  release << true
  page = reader.value
  writer.value
  assert_equal([], page.fetch('entries'), 'The paused selection was not the empty prefix')
  assert_equal([0, 0, false], page.values_at('cursor', 'through', 'has_more'),
    'The broker combined an earlier empty selection with a later stack boundary')
  after = session.stack_read(after: 0, limit: 128)
  assert_equal([1, 1, false], after.values_at('cursor', 'through', 'has_more'))
  assert_equal([1], after.fetch('entries').map { |entry| entry.fetch('seq') })
ensure
  release << true
  reader&.join(2)
  writer&.join(2)
  session&.close
end
puts 'PASS native broker stack pages: one consistent snapshot during a controlled concurrent append, then the complete next read (offline fixture only)'
