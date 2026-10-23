require_relative 'native_tasks'
require_relative 'assertions'
require_relative '../../lib/game_room_background'

module GameRoomTest
  module NativeBackgroundCapacity
    extend Assertions

    # Real native Tasks limits and the unchanged application FIFO. No HTTP or
    # replacement Work implementation; all blocked tasks belong to this scope.
    def self.with(backlog_count, runtime: nil, worker: nil)
      runtime ||= TestTaskRuntime.new("background-capacity-#{backlog_count}")
      works, entered, release = [], Queue.new, Queue.new
      make_work = -> { GameRoomBackground::Work.new(runtime: runtime).tap { |work| works << work } }
      worker ? works << worker : worker = make_work.call
      blockers = 4.times.map do
        make_work.call.tap { |work| work.start { entered << true; release.pop } }
      end
      Timeout.timeout(5) { blockers.length.times { entered.pop } }
      backlog = backlog_count.times.map { make_work.call.tap { |work| work.start { :unused } } }
      pending = GameRoomBackground.const_get(:Pending)
      assert_equal(backlog_count, pending.instance_variable_get(:@items).size,
        'The actual native worker/FIFO capacity was not reached')
      free_capacity = lambda do
        backlog.each(&:close)
        blockers.length.times { release << true }
        blockers.each { |work| wait_background_work(work) }
      end
      yield worker, free_capacity, runtime
    ensure
      4.times { release << true } if release
      works.to_a.each(&:close)
      works.to_a.each { |work| wait_background_work(work) }
      runtime&.close
    end

    def self.until_true
      Timeout.timeout(5) { Thread.pass until yield }
    end
  end
end
