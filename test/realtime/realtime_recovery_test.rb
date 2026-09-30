require_relative "../support/realtime_channel"
require_relative "../../lib/realtime/operation"

now = 0.0
workers = []
factory = -> { workers << ChannelWork.new; workers.last }
operation = GameRoomRealtime::Operation.new(clock: -> { now }, factory: factory)
operation.start(:setup) { :old }
now = 8.1
assert(operation.expired?, 'native setup without a result has no deadline')
operation.cancel
operation.start(:replacement) { :new }
workers.first.finish
assert(operation.take == nil, 'late cancelled setup became current')
workers.last.finish
assert(operation.take == [:new, nil, :replacement], 'replacement result lost')

operation.start(:stuck_one) { 1 }
operation.cancel
operation.start(:stuck_two) { 2 }
operation.cancel
before = workers.length
20.times { operation.cancel; operation.start(:extra) { 3 } }
assert(workers.length == before && operation.busy?, 'hung native calls created unbounded threads')
workers[-2].finish
assert(!operation.busy?, 'completed abandoned worker did not unblock recovery')
operation.close

# Transient PeerUnavailable should retry promptly, without a request every frame.
now = 0.0
work, program = ChannelWork.new, ChannelProgram.new('Alice')
channel = GameRoomRealtime::Channel.new(program: program, match: 'match', owner: 'Alice', viewer: 'Alice',
  clock: -> { now }, members: -> { %w[Alice Bob] }, work: work)
channel.tick; work.finish; channel.tick; work.finish; channel.tick
session = channel.instance_variable_get(:@session)
attempts = []
session.define_singleton_method(:invite) do |_user|
  attempts << now
  raise EltenAPI::Communication::PeerUnavailable, 'PeerUnavailable' if attempts.length <= 2
end
work.finish; channel.tick
now = 0.1
channel.tick
assert(!work.operation, 'invite retries flood the relay')
now = 0.6
channel.tick
assert(work.operation, 'PeerUnavailable still delays first retry by five seconds')
work.finish; channel.tick
now = 1.7
channel.tick; work.finish; channel.tick
assert(attempts == [0.0, 0.6, 1.7], 'bounded invitation backoff was not respected')
channel.close

# A queued registration that missed its deadline does not block a new attempt.
# Running the obsolete worker later must not call the cached native factory.
now = 0.0
workers = []
factory = -> { workers << ChannelWork.new; workers.last }
program = ChannelProgram.new('Alice')
channel = GameRoomRealtime::Channel.new(program: program, match: 'match', owner: 'Alice', viewer: 'Alice',
  clock: -> { now }, members: -> { ['Alice'] }, work_factory: factory)
channel.tick
now = 8.1
channel.tick
assert(workers.length == 2, 'stuck registration blocked recovery')
now = 8.7
channel.tick; workers.last.finish; channel.tick; workers.last.finish; channel.tick
current = program.endpoints.last
assert(channel.connected?, 'replacement setup could not complete')
workers.first.finish
channel.tick
assert(channel.connected? && !current.closed?, 'late old registration replaced the working channel')
assert(program.endpoints == [current] && program.released.empty?, 'obsolete queued registration touched an endpoint')
channel.close

# An old departure can hang independently of a successfully accepted session.
# Attach first, then retire only the obsolete leave call on its deadline.
now = 0.0
work, program = ChannelWork.new, ChannelProgram.new('Bob')
guest = GameRoomRealtime::Channel.new(program: program, match: 'match', owner: 'Alice', viewer: 'Bob',
  clock: -> { now }, members: -> { %w[Alice Bob] }, work: work)
guest.tick; work.finish; guest.tick
endpoint = program.endpoints.first
old_session = ChannelSession.new('old-departure', 'Bob', %w[Alice Bob])
endpoint.enqueue(ChannelInvitation.new(old_session))
guest.tick; work.finish; guest.tick
replacement = ChannelSession.new('replacement-before-leave', 'Bob', %w[Alice Bob])
endpoint.enqueue(ChannelInvitation.new(replacement))
guest.tick; work.finish; guest.tick
assert(guest.instance_variable_get(:@session).equal?(replacement) && work.operation, 'new session waits for old leave')
now = 8.1
guest.tick
assert(guest.connected? && !endpoint.closed?, 'hung obsolete leave closed the new session')
work.finish
guest.tick
assert(guest.instance_variable_get(:@session).equal?(replacement), 'late departure reverted the new session')
guest.close

puts 'PASS realtime recovery: bounded workers, ignored late results, setup deadline, fast bounded invite retry'
