require_relative '../support/realtime_channel'

class CachedChannelProgram < ChannelProgram
  def communication
    @cached = nil if @cached&.closed?
    @cached ||= super
  end
end

[:timeout, :new_screen].each do |scenario|
  now = 0.0
  workers = []
  factory = -> { workers << ChannelWork.new; workers.last }
  program = CachedChannelProgram.new('Alice')
  build = -> { GameRoomRealtime::Channel.new(program: program, match: 'match', owner: 'Alice', viewer: 'Alice',
    clock: -> { now }, members: -> { ['Alice'] }, work_factory: factory) }
  old = channel = build.call
  channel.tick
  stale = workers.first
  if scenario == :timeout
    now = 8.1; channel.tick
    now = 8.7
  else
    old.close
    channel = build.call
  end
  channel.tick; workers.last.finish; channel.tick; workers.last.finish; channel.tick
  assert(channel.connected?, "#{scenario}: successor not connected")
  endpoint = program.endpoints.last
  stale.finish
  assert(channel.connected? && !endpoint.closed?, "#{scenario}: stale setup closed successor")
  assert(program.endpoints.size == 1, 'cancelled setup created another endpoint')
  channel.close
  assert(program.released == [endpoint] && endpoint.closes == 1, 'successor leaked')
end

# A genuinely in-flight constructor must finish/clean up before the next
# setup consults the same native cache. Neither close nor tick waits for it.
program = CachedChannelProgram.new('Alice')
entered, resume = Queue.new, Queue.new
program.creation_hook = -> { entered << true; resume.pop }
first = GameRoomRealtime::Channel.new(program: program, match: 'old', owner: 'Alice', viewer: 'Alice',
  clock: -> { 0.0 }, members: -> { ['Alice'] })
work = ChannelWork.new
first.tick
entered.pop
first.close
next_channel = GameRoomRealtime::Channel.new(program: program, match: 'new', owner: 'Alice', viewer: 'Alice',
  clock: -> { 0.0 }, members: -> { ['Alice'] }, work: work)
next_channel.tick
program.creation_hook = nil
thread = Thread.new { work.finish }
resume << true
assert(thread.join(3), 'setup ownership deadlocked')
next_channel.tick; work.finish; next_channel.tick
assert(next_channel.connected? && program.endpoints.length == 2, 'in-flight successor failed')
assert(program.endpoints.first.closed? && !program.endpoints.last.closed?, 'wrong endpoint retired')
next_channel.close
assert(program.released == program.endpoints, 'orphan or successor leaked')
puts 'PASS cached endpoint ownership: queued timeout, next screen, in-flight close and successor'
