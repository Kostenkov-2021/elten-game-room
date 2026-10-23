require 'timeout'
require_relative '../support/native_live_sessions'

broker = NativeLiveSessionsBroker.new
broker.automatic_delivery = false
endpoint = broker.endpoint('Alice')
view = endpoint.create(metadata: {}, participant_metadata: {}, capacity: 2,
  visibility: :public, discovery_metadata: {}, stack_entries: 2,
  stack_entry_bytes: 1024)
core = broker.cores.fetch(view.id)
arrived, release, results = Queue.new, Queue.new, Queue.new
serial = Mutex.new
gate = Object.new
gate.define_singleton_method(:synchronize) do |&block|
  arrived << true
  release.pop
  serial.synchronize(&block)
end
core.mutex = gate
workers = []
begin
  2.times do
    workers << Thread.new do
      begin
        results << view.stack_push({'value' => 'original'}, message_id: 'same-operation')
      rescue StandardError => error
        results << error
      end
    end
  end
  # Both attempts reach the storage lock before either can commit. This is
  # an offline broker regression, not concurrent live SDK/server execution.
  Timeout.timeout(5) { 2.times { arrived.pop } }
  2.times { release << true }
  workers.each { |worker| assert(worker.join(5), 'Owned broker worker did not finish') }
  replies = 2.times.map { results.pop }
  assert(replies.none? { |reply| reply.is_a?(Exception) }, "Broker push failed: #{replies.inspect}")
  assert_equal([1, 1], replies.map { |reply| reply.dig('entry', 'seq') }.sort,
    'Concurrent retries did not return one original receipt')
  assert_equal(1, core.entries.size, 'Concurrent retries stored duplicate entries')
  assert_equal(1, core.last_seq)
  assert_equal(1, core.dedup.fetch(['Alice', 'same-operation']))
ensure
  workers.each { |worker| worker.kill if worker.alive? }
  workers.each { |worker| worker.join(5) }
  core.mutex = serial
end

second = view.stack_push({'value' => 'next'}, message_id: 'other-operation')
assert_equal(2, second.dig('entry', 'seq'))
retry_at_capacity = view.stack_push({'value' => 'original'}, message_id: 'same-operation')
assert_equal(1, retry_at_capacity.dig('entry', 'seq'), 'A full stack rejected an existing receipt')
assert_equal(2, core.entries.size)
assert_raises(EltenAPI::LiveSessions::StackFull) do
  view.stack_push({'value' => 'extra'}, message_id: 'new-operation')
end
puts 'PASS offline native broker: concurrent same-UUID attempts have one commit/receipt; distinct UUIDs and duplicate-at-capacity remain correct'
