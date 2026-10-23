require_relative '../../lib/invitation_repository'
require_relative '../support/assertions'
include GameRoomTest::Assertions

transport = Object.new
def transport.pending_invitations; []; end
rows = []
repository = InvitationRepository.new(transport: transport, current_user: -> { 'Bob' },
  notification_source: ->(*) { rows })
table = {'__id' => 7, 'status' => 'waiting', '__live_session_id' => 'native'}
base = {'__id' => 1, 'table_id' => 7, 'live_session_id' => 'native',
  'sender' => 'Alice', 'recipient' => 'Bob', 'expires_at' => 101}
responses = -> { repository.instance_variable_get(:@responses) }
first = repository.respond(base, recipient: 'Bob', response: 'rejected', now: 100)
assert_equal(first, repository.respond(base, recipient: 'Bob', response: 'accepted', now: 399))
repository.pending_for('Bob', tables: [table], now: 399)
assert_equal(1, responses.call.size, 'Invitation expiry shortened the response retry horizon')
repository.pending_for('Bob', tables: [table], now: 400)
assert_equal(0, responses.call.size, 'A settled finite-expiry response survived both expiry and retry horizon')

long = base.merge('__id' => 2, 'expires_at' => 10_000)
repository.respond(long, recipient: 'Bob', response: 'accepted', now: 500)
rows << long
assert_equal([], repository.pending_for('Bob', tables: [table], now: 900))
assert_equal('accepted', repository.respond(long, recipient: 'Bob', response: 'rejected', now: 900)['response'])
assert_equal(1, responses.call.size, 'A valid long-lived invitation lost its original decision')

# Legacy rows without an expiry cannot safely be retired by a guessed lifetime.
[nil, 0].each_with_index do |expiry, index|
  row = base.merge('__id' => index + 3, 'expires_at' => expiry)
  repository.respond(row, recipient: 'Bob', response: 'rejected', now: 600)
  rows << row
end
assert_equal([], repository.pending_for('Bob', tables: [table], now: 20_000))
assert_equal(2, responses.call.size, 'Pruning discarded unresolved legacy lifetime semantics')

# Repeated finite invitations remain bounded without dropping any still-valid
# decision. Distinct sender/native/table scopes retain independent responses.
2_000.times do |index|
  now = 30_000 + index * (InvitationResponseOutbox::TTL + 1)
  row = base.merge('__id' => 10 + index, 'expires_at' => now + 1)
  repository.respond(row, recipient: 'Bob', response: 'rejected', now: now)
end
assert_equal(3, responses.call.size, 'Expired scopes accumulated in one active repository')
1_100.times do |index|
  row = base.merge('__id' => 3_000 + index, 'expires_at' => 2_000_000)
  repository.respond(row, recipient: 'Bob', response: 'accepted', now: 1_000_000)
end
assert_equal(1_102, responses.call.size, 'A global item limit evicted still-valid responses')
other = base.merge('__id' => 3_000, 'sender' => 'Carol', 'live_session_id' => 'other-native', 'expires_at' => 2_000_000)
assert_equal('rejected', repository.respond(other, recipient: 'Bob', response: 'rejected', now: 1_000_000)['response'])
assert_equal('accepted', repository.respond(other.merge('sender' => 'Alice', 'live_session_id' => 'native'),
  recipient: 'Bob', response: 'rejected', now: 1_000_000)['response'])

# A failed delivery is still owned by the separate outbox and is not cancelled
# when the invitation expires. Retrying the repository does not change it.
module EltenAPI
  module LiveSessions
    class Error < StandardError; end
    class TimeoutError < Error; end
  end
end
class RetentionRetryWorker
  def take; @result.tap { @result = nil }; end
  def busy?; false; end
  def closed?; false; end
  def start(&operation); @result = [operation.call, nil]; end
end
now, calls = 100.0, []
outbox = InvitationResponseOutbox.new(worker: RetentionRetryWorker.new, clock: -> { now }, current_user: -> { 'Bob' })
sender = ->(row, response) do
  calls << [row['__id'], response]
  raise EltenAPI::LiveSessions::TimeoutError, 'unknown acknowledgement' if calls.size == 1
end
retrying = InvitationRepository.new(transport: transport, response_sender: sender, response_outbox: outbox, current_user: -> { 'Bob' })
retrying.respond(base, recipient: 'Bob', response: 'rejected', now: now)
now = 116
retrying.pending_for('Bob', tables: [table], now: now)
assert_equal('rejected', retrying.respond(base, recipient: 'Bob', response: 'accepted', now: now)['response'])
outbox.tick
outbox.tick
assert_equal([[1, 'rejected'], [1, 'rejected']], calls, 'Expiry changed or cancelled the pending delivery')
puts 'PASS finite response retirement, retry horizon, long/legacy invitations, independent scopes and bounded expired traffic'
