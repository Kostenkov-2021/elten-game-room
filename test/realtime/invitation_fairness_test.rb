require_relative '../support/realtime_event_channel'

now = 0.0
work, program = ChannelWork.new, ChannelProgram.new('Alice')
members = %w[Alice Watcher Bob Offline Carol Later]
channel = GameRoomRealtime::EventChannel.new(program: program, match: 'match', owner: 'Alice', viewer: 'Alice',
  clock: -> { now }, members: -> { members }, work: work)
channel.enable_events('test', routing: :peers)
channel.required_members = %w[Bob Offline Carol]
channel.tick; work.finish; channel.tick; work.finish
session = program.endpoints.last.instance_variable_get(:@created)
attempts = []
session.define_singleton_method(:invite) do |user|
  attempts << [now, user]
  if %w[Watcher Offline].include?(user)
    raise EltenAPI::Communication::PeerUnavailable, 'PeerUnavailable'
  end
  participants << ChannelParticipant.new(participants.length, user)
end
channel.tick
15.times do
  now += 2.1
  work.finish if work.operation
  channel.tick
end
assert(attempts.first(3).map(&:last) == %w[Bob Offline Carol], "players not prioritized: #{attempts}")
assert(attempts.first(5).map(&:last).sort == members.drop(1).sort, 'spectators starved by required peer')
%w[Watcher Offline].each do |name|
  retries = attempts.select { |_, user| user == name }
  assert(retries.size >= 2, 'unavailable member never retried')
  retries.each_cons(2) { |a, b| assert(b[0] - a[0] > 2.1, 'failure cooldown measured from start') }
end
assert(!channel.required_members_present?, 'unavailable required peer silently omitted')
session.participants << ChannelParticipant.new(99, 'Offline')
assert(channel.required_members_present?, 'missing optional spectator blocks readiness')
channel.close
puts 'PASS invitation priority, fair failed retries, completion cooldown and required/optional readiness'
