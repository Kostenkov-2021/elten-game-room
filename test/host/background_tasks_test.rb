require_relative '../support/native_tasks'
require_relative '../support/assertions'
require_relative '../../lib/game_room_background'
Object.include(GameRoomTest::Assertions)

# Observe admission order while leaving native worker creation/execution intact.
module TaskAdmissionTrace
  def start(owner: nil, **options, &block)
    super.tap { ($task_admissions ||= []) << owner }
  end
end
EltenAPI::Tasks.singleton_class.prepend(TaskAdmissionTrace)

def await_queue(queue)
  Timeout.timeout(3) { queue.pop }
end

runtime = TestTaskRuntime.new('Task-Owner')
works = []
make = ->(owner = runtime) { works << GameRoomBackground::Work.new(runtime: owner); works.last }
entered, release, completed = Queue.new, Queue.new, Queue.new
begin
  # A completed but unread result is still busy; nil/false and errors survive.
  work = make.call
  [nil, false, 41].each do |value|
    assert(work.start { [value, Programs.current_runtime] })
    wait_background_work(work)
    assert(work.busy? && !work.start { raise 'Overwrote pending outcome' })
    assert_equal([[value, runtime], nil], work.take)
    assert(work.take.nil? && !work.busy?)
  end
  failure = RuntimeError.new('original failure')
  work.start { raise failure }
  wait_background_work(work)
  assert(work.take.last.equal?(failure), 'Programming error lost its identity')

  running = 4.times.map do |id|
    current = make.call
    current.start { entered << id; release.pop; completed << id; id }
    current
  end
  assert_equal([0, 1, 2, 3], 4.times.map { await_queue(entered) }.sort)
  starts = []
  queued = 3.times.map do |id|
    current = make.call
    current.start { starts << id; entered << id; release.pop; completed << id; id }
    current
  end
  100.times { queued.each { |item| assert(item.busy? && item.take.nil?) } }
  assert(starts.empty?, 'More than four native workers ran in one scope')
  # A different runtime with the same UUID shares the host limit.
  same_uuid = TestTaskRuntime.new('TASK-OWNER')
  shared = make.call(same_uuid)
  shared.start { :shared }
  assert(shared.instance_variable_get(:@handle).nil?)
  independent = make.call(TestTaskRuntime.new('another-app'))
  independent.start { :independent }
  wait_background_work(independent)
  assert_equal([:independent, nil], independent.take)

  # Closing a running uncertain write never interrupts it or frees its slot.
  running.first.close
  assert(running.first.take.nil?)
  queued.first.close
  10.times { queued.last.busy? }
  assert(starts.empty?)
  4.times { release << true }
  assert_equal([0, 1, 2, 3], 4.times.map { await_queue(completed) }.sort)
  Timeout.timeout(3) do
    until starts.length == 2
      queued.last.busy?
      Thread.pass
    end
  end
  assert_equal([1, 2], 2.times.map { await_queue(entered) }.sort)
  # Admission is FIFO; execution itself is scheduled by the OS.
  assert_equal(queued.drop(1), $task_admissions.select { |item| queued.include?(item) })
  assert(queued.first.closed? && !starts.include?(0), 'Closed queued work ran')
  2.times { release << true }
  2.times { await_queue(completed) }
  queued.drop(1).each { |item| wait_background_work(item); assert(item.take.last.nil?) }
  wait_background_work(shared)
  assert_equal([:shared, nil], shared.take)
  assert(!running.first.start { raise 'Reopened closed work' })

  # Runtime teardown discards both running and queued outcomes, but a started
  # operation can still finish its server write exactly once.
  teardown = TestTaskRuntime.new('teardown')
  finishing = 4.times.map do
    item = make.call(teardown)
    item.start { entered << true; release.pop; completed << :written }
    item
  end
  4.times { await_queue(entered) }
  deferred = make.call(teardown)
  deferred.start { raise 'Started after runtime teardown' }
  teardown.close
  assert(finishing.all?(&:closed?) && deferred.closed?)
  4.times { release << true }
  assert_equal([:written] * 4, 4.times.map { await_queue(completed) })
  finishing.each { |item| wait_background_work(item); assert(item.take.nil?) }

  # A bounded backlog fails before running an extra operation, and closing
  # queued owners releases its capacity. No hidden retry of the action occurs.
  saturated = TestTaskRuntime.new('saturated')
  4.times do
    make.call(saturated).start { entered << true; release.pop; completed << true }
  end
  4.times { await_queue(entered) }
  backlog = 128.times.map do
    item = make.call(saturated)
    assert(item.start { raise 'Abandoned queued action ran' })
    item
  end
  overflow = make.call(saturated)
  assert_raises(EltenAPI::Tasks::Busy) { overflow.start { raise 'Overflow ran' } }
  assert(!overflow.busy?)
  backlog.each(&:close)
  assert(overflow.start { :after_capacity })
  overflow.close
  4.times { release << true }
  4.times { await_queue(completed) }
ensure
  32.times { release << true }
  works.each(&:close)
  works.each { |item| wait_background_work(item) }
end
assert(runtime.managed_resources.size == 0, 'Closed owners leaked native registrations')
puts 'PASS native Tasks: outcomes/errors, four workers per UUID, queue bound, closing, runtime teardown and uncertain writes'
