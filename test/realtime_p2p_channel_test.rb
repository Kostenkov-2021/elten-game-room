require_relative 'support/realtime_channel'

[{}, {'p2p_enabled' => false, 'p2p_participants_limit' => 12},
 {'p2p_enabled' => true}, {'p2p_enabled' => true, 'p2p_participants_limit' => 0},
 {'p2p_enabled' => true, 'p2p_participants_limit' => 12}].each do |options|
  now = 0.0
  workers, program = [], ChannelProgram.new('Alice')
  channel = GameRoomRealtime::Channel.new(program: program, match: 'match', owner: 'Alice', viewer: 'Alice',
    clock: -> { now }, members: -> { ['Alice'] }, work_factory: -> { workers << ChannelWork.new; workers.last })
  # Pong creates its endpoint early, before replay is available.
  channel.tick
  channel.configure_p2p(options)
  workers.last.finish; channel.tick; workers.last.finish; channel.tick
  expected = {metadata: {'gr_realtime' => 1, 'match' => 'match'}, capacity: 32, public: false, encryption: 192}
    .merge(GameRoomRealtime::P2POptions.session_options(options))
  assert(channel.connected? && program.endpoints.first.creates == [expected], 'native P2P contract mismatch')
  10.times { channel.configure_p2p(options); channel.tick }
  assert(program.endpoints.length == 1 && !workers.last.operation, 'unchanged replay reconnects or makes extra requests')
  channel.reconnect(reason: 'test')
  channel.tick
  now = 1.0
  channel.tick; workers.last.finish; channel.tick; workers.last.finish; channel.tick
  assert(channel.connected? && program.endpoints.last.creates == [expected], 'reconnect lost P2P configuration')
  assert(program.endpoints.length == 2 && program.endpoints.first.closed?, 'reconnect leaked endpoint')
  channel.close
end

# A setting change during queued creation must neither alter that request
# in place nor adopt its late result as the new session.
now, workers, program = 0.0, [], ChannelProgram.new('Alice')
channel = GameRoomRealtime::Channel.new(program: program, match: 'match', owner: 'Alice', viewer: 'Alice',
  clock: -> { now }, members: -> { ['Alice'] }, work_factory: -> { workers << ChannelWork.new; workers.last })
channel.tick; workers.last.finish; channel.tick
old_worker, old_endpoint = workers.last, program.endpoints.first
channel.configure_p2p('p2p_enabled' => true)
channel.tick
now = 1.0
channel.tick; workers.last.finish; channel.tick; workers.last.finish; channel.tick
current = channel.instance_variable_get(:@session)
old_worker.finish
channel.tick
assert(old_endpoint.creates.first[:p2p].nil?, 'queued relay request changed underneath worker')
assert(old_endpoint.instance_variable_get(:@created).state == :closed, 'late session leaked')
assert(channel.connected? && channel.instance_variable_get(:@session).equal?(current), 'late result replaced current session')
assert(program.endpoints.last.creates.first[:p2p] == :full, 'replacement did not use full P2P')
channel.configure_p2p('p2p_enabled' => false)
channel.tick
now = 2.0
channel.tick; workers.last.finish; channel.tick; workers.last.finish; channel.tick
assert(channel.connected? && !program.endpoints.last.creates.first.key?(:p2p), 'switch back to relay failed')
channel.close

# Guests accept the owner's native session; they never create a private
# competing session or alter the invited session's P2P mode.
work, program = ChannelWork.new, ChannelProgram.new('Bob')
guest = GameRoomRealtime::Channel.new(program: program, match: 'match', owner: 'Alice', viewer: 'Bob',
  clock: -> { 0.0 }, members: -> { %w[Alice Bob] }, work: work)
guest.configure_p2p('p2p_enabled' => true, 'p2p_participants_limit' => 8)
guest.tick; work.finish; guest.tick
endpoint = program.endpoints.first
invitation = ChannelInvitation.new(ChannelSession.new('full-session', 'Bob', %w[Alice Bob]))
endpoint.enqueue(invitation)
guest.tick; work.finish; guest.tick
assert(guest.connected? && invitation.accepts == 1 && endpoint.creates.empty?, 'guest P2P bypassed native invitation')
guest.close
puts 'PASS P2P channel: off unchanged, full, custom/unlimited, reconnect, queued setting change and guest invitation'
