require_relative '../support/native_background_capacity'
require_relative '../../lib/invitation_repository'
include GameRoomTest::Assertions

module EltenAPI::LiveSessions
  class Error < StandardError; end
  class TimeoutError < Error; end
end

[0, 128].each do |backlog_count|
  GameRoomTest::NativeBackgroundCapacity.with(backlog_count) do |worker, free_capacity|
    now, calls = 100.0, []
    row = {'__id' => 901, 'table_id' => 7, 'live_session_id' => 'response-capacity',
      'sender' => 'Alice', 'recipient' => 'Bob', 'expires_at' => 400}
    outbox = InvitationResponseOutbox.new(worker: worker, clock: -> { now }, current_user: -> { 'Bob' })
    repository = InvitationRepository.new(transport: Object.new, response_outbox: outbox,
      current_user: -> { 'Bob' }, response_sender: lambda do |snapshot, response|
        calls << [snapshot['sender'], response]
        raise EltenAPI::LiveSessions::TimeoutError, 'Unknown first acknowledgement' if calls.one?
      end)
    decision = repository.respond(row, recipient: 'Bob', response: 'rejected', now: now)
    now = 115.0
    outbox.tick
    assert_equal([['Alice', 'rejected']], calls, 'A waiting retry bypassed native capacity')
    job = outbox.instance_variable_get(:@jobs).values.fetch(0)
    assert_equal(backlog_count.zero? ? :sending : :pending, job[:state],
      'A response was marked as sending without admission')
    assert(decision.equal?(repository.respond(row, recipient: 'Bob', response: 'accepted', now: now)),
      'Backpressure changed the original immutable decision')
    free_capacity.call
    Timeout.timeout(5) do
      until job[:state] == :delivered
        outbox.tick
        Thread.pass
      end
    end
    3.times { outbox.tick }
    assert_equal([['Alice', 'rejected'], ['Alice', 'rejected']], calls,
      'The recovered response was lost or delivered more than once')
    assert(decision.equal?(repository.respond(row, recipient: 'Bob', response: 'accepted', now: now)))
  end
end

# A worker may also decline admission without raising. That is not a send.
class DecliningResponseWorker
  attr_reader :calls
  def initialize; @calls = 0; end
  def take; nil; end
  def busy?; false; end
  def closed?; false; end
  def start; @calls += 1; false; end
end
worker = DecliningResponseWorker.new
now = 100.0
outbox = InvitationResponseOutbox.new(worker: worker, clock: -> { now }, current_user: -> { 'Bob' })
outbox.submit({'__id' => 902, 'table_id' => 7, 'sender' => 'Alice', 'recipient' => 'Bob'}, 'rejected') do
  raise EltenAPI::LiveSessions::TimeoutError, 'Queue this reply'
end
now = 115.0
2.times { outbox.tick }
assert_equal(2, worker.calls, 'Declined admission stranded the retry')
assert_equal(:pending, outbox.instance_variable_get(:@jobs).values.fetch(0)[:state])
puts 'PASS actual native task/FIFO capacity recovery, immutable invitation decision, exact-once retry and declined admission'
