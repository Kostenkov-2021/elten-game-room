require_relative '../support/native_tasks'
require_relative '../support/assertions'
require_relative '../../lib/realtime/operation'
include GameRoomTest::Assertions

# Closing the actual host Work hides its result, not its running thread.
# A manual worker that stays busy after close cannot establish this bound.
runtime = TestTaskRuntime.new('realtime-operation-native-lifetime')
works = []
factory = -> { GameRoomBackground::Work.new(runtime: runtime).tap { |work| works << work } }
lane = GameRoomRealtime::Operation.new(clock: -> { 0.0 }, factory: factory)
entered, first_release, second_release = Queue.new, Queue.new, Queue.new
begin
  assert(lane.start(:first) { entered << :first; first_release.pop; :obsolete_first }, 'first request did not start')
  assert_equal(:first, Timeout.timeout(3) { entered.pop })
  lane.cancel
  assert(lane.start(:second) { entered << :second; second_release.pop; :obsolete_second }, 'one replacement should be allowed')
  assert_equal(:second, Timeout.timeout(3) { entered.pop })
  lane.cancel
  20.times do
    lane.cancel
    assert(!lane.start(:excess) { entered << :excess }, 'more than two unfinished native calls were admitted')
  end
  assert(entered.empty? && works.size == 2 && lane.busy?, 'abandoned work escaped the lane limit')

  first_release << true
  Timeout.timeout(3) { Thread.pass while lane.busy? }
  assert(lane.start(:current) { :current }, 'completed abandoned work did not free a replacement slot')
  result = Timeout.timeout(3) do
    loop do
      outcome = lane.take
      break outcome if outcome
      Thread.pass
    end
  end
  assert_equal([:current, nil, :current], result)
  second_release << true
  retired = works[1]
  Timeout.timeout(3) do
    until retired.closed?
      lane.busy?
      Thread.pass
    end
  end
  assert_equal(nil, lane.take)
ensure
  lane.close
  first_release << true
  second_release << true
  runtime.close
  works.each { |work| wait_background_work(work) }
end

# Four unrelated native tasks delay this lane before its block can run.
# Cancellation must still suppress that block, without killing any request.
runtime = TestTaskRuntime.new('realtime-operation-native-queued-cancel')
occupied, release, forbidden = Queue.new, Queue.new, Queue.new
blockers, works = [], []
factory = -> { GameRoomBackground::Work.new(runtime: runtime).tap { |work| works << work } }
lane = GameRoomRealtime::Operation.new(clock: -> { 0.0 }, factory: factory)
begin
  4.times do
    blocker = GameRoomBackground::Work.new(runtime: runtime)
    blockers << blocker
    assert(blocker.start { occupied << true; release.pop }, 'capacity fixture failed to start')
    Timeout.timeout(3) { occupied.pop }
  end
  assert(lane.start(:queued) { forbidden << true }, 'native capacity should queue the operation')
  lane.cancel
  release << true
  assert(lane.start(:fresh) { :fresh }, 'a fresh generation could not be queued')
  result = Timeout.timeout(3) do
    loop do
      outcome = lane.take
      break outcome if outcome
      Thread.pass
    end
  end
  assert_equal([:fresh, nil, :fresh], result)
  assert(forbidden.empty?, 'an obsolete queued RPC executed after capacity became free')
ensure
  lane.close
  4.times { release << true }
  runtime.close
  (blockers + works).each { |work| wait_background_work(work) }
end

puts 'PASS native operation lifetime: at most two in-flight calls, recovery, stale results and queued cancellation'
