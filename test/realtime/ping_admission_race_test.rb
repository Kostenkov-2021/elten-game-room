require_relative '../support/native_background_capacity'
require_relative '../support/widget'
require_relative '../../lib/game_room_ping'
include GameRoomTest::Assertions

# Keep the actual Work/native Tasks. The test-only return barrier schedules
# a possible native race: the probe has begun before start returns to its UI.
class PingNativeReturnBarrier < GameRoomBackground::Work
  def initialize(entered:, **options)
    @entered = entered
    super(**options)
  end
  def start(&operation)
    accepted = super
    Timeout.timeout(5) { @entered.pop } if accepted
    accepted
  end
end

runtime = TestTaskRuntime.new('ping-admission-return-race')
entered, release = Queue.new, Queue.new
work = PingNativeReturnBarrier.new(runtime: runtime, entered: entered)
now, program = 100.0, Object.new
service = GameRoomPing.new(program, worker: work, clock: -> { now }, probe: -> {
  entered << true
  release.pop
  now += 0.042
  true
})
begin
  assert(service.request(program), 'Native ping was not admitted')
  release << true
  message = nil
  GameRoomTest::NativeBackgroundCapacity.until_true { message = service.poll(program) }
  assert_equal('HTTP ping: 42 ms.', message, 'Admission result overwrote the running probe timestamp')
ensure
  release << true
  work.close
  wait_background_work(work)
  runtime.close
end
puts 'PASS ping native start-return race: admission flag and worker timing remain independent'
