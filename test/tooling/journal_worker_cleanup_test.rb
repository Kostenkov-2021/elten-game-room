require 'stringio'
require_relative '../support/assertions'
require_relative '../support/tournament_operation_journal'
include GameRoomTest::Assertions

JournalCleanupStream = Struct.new(:failure, :closed, :closes) do
  def initialize(failure = nil, closed: false); super(failure, closed, 0); end
  def gets; "READY\n"; end
  def closed?; closed; end
  def close
    self.closes += 1
    self.closed = true
    raise failure if failure
  end
end
JournalCleanupWaiter = Struct.new(:pid, :running, :joined, :failure, :joins) do
  def initialize(running: true, joined: true, failure: nil)
    # Never provide a real PID, even if an interception unexpectedly fails.
    super(Object.new, running, joined, failure, [])
  end
  def alive?; running; end
  def join(seconds = nil)
    joins << seconds
    raise failure if failure
    joined ? self : nil
  end
end
subject = Object.new.extend(TournamentOperationJournalProcesses)
def subject.equal(expected, actual); raise 'Unexpected worker readiness' unless expected == actual; end

exercise = lambda do |primary: nil, close_error: nil, kill_error: nil, join_error: nil,
    join_timeout: false, already_closed: false, running: true|
  children = Array.new(2) do
    [JournalCleanupStream.new(nil, closed: already_closed),
      JournalCleanupStream.new(nil, closed: already_closed), JournalCleanupWaiter.new(running: running)]
  end
  children[0][0].failure = close_error
  children[0][2].failure = join_error
  children[0][2].joined = !join_timeout
  original_open, original_kill, original_stderr = Open3.method(:popen2e), Process.method(:kill), $stderr
  pending, signals, warnings = children.dup, [], StringIO.new
  result, observed, expected_result = nil, nil, Object.new
  Open3.define_singleton_method(:popen2e) { |*| pending.shift || raise('Unexpected child creation') }
  Process.define_singleton_method(:kill) do |signal, pid|
    raise 'Unowned signal' unless signal == 'KILL' && children.any? { |child| child.last.pid.equal?(pid) }
    signals << pid
    raise kill_error if kill_error && children[0].last.pid.equal?(pid)
    1
  end
  $stderr = warnings
  begin
    result = subject.workers([['claim', 'first'], ['claim', 'second']]) do
      raise primary if primary
      expected_result
    end
  rescue StandardError => error
    observed = error
  ensure
    Open3.define_singleton_method(:popen2e, original_open)
    Process.define_singleton_method(:kill, original_kill)
    $stderr = original_stderr
  end
  children.each do |input, output, waiter|
    assert(input.closed? && output.closed?, 'a stream remained open')
    assert_equal(already_closed ? 0 : 1, input.closes)
    assert_equal(already_closed ? 0 : 1, output.closes)
    assert_equal([5], waiter.joins, 'cleanup must join each child with a bound')
  end
  assert_equal(running ? 2 : 0, signals.size)
  {error: observed, result: result, expected_result: expected_result, warnings: warnings.string}
end

normal = exercise.call
assert(normal[:result].equal?(normal[:expected_result]) && !normal[:error], 'successful result changed')
assert(exercise.call(already_closed: true, running: false)[:error].nil?, 'already-reaped cleanup failed')

primary = TypeError.new('original scenario failure')
raced = exercise.call(primary: primary, kill_error: Errno::ESRCH.new)
assert(raced[:error].equal?(primary), 'exited worker masked the primary error')
assert(raced[:warnings].empty?, 'an already-exited worker is not a cleanup failure')

close_error = IOError.new('input close failed')
multiple = exercise.call(primary: primary, close_error: close_error, kill_error: Errno::EPERM.new,
  join_error: RuntimeError.new('join failed'))
assert(multiple[:error].equal?(primary), 'secondary cleanup failure replaced the primary error')
%w[input EPERM join].each { |text| assert(multiple[:warnings].include?(text), 'cleanup failure was hidden') }
assert(exercise.call(close_error: close_error)[:error].equal?(close_error), 'cleanup-only failure disappeared')
timeout = exercise.call(join_timeout: true)
assert(timeout[:error]&.message == 'Owned test worker cleanup timed out', 'unbounded or hidden cleanup wait')
assert(exercise.call(primary: primary, join_timeout: true)[:error].equal?(primary), 'timeout masked the primary error')

begin
  raise ArgumentError, 'unrelated caller rescue'
rescue ArgumentError
  nested = exercise.call(close_error: close_error)
end
assert(nested[:error].equal?(close_error), 'An unrelated caller rescue hid the successful worker body cleanup failure')

puts 'PASS journal worker cleanup: exited child race, all children, bounded waits, diagnostics and primary failure'
