require 'stringio'
require_relative '../support/assertions'
require_relative '../tournaments/drafts_test'
require_relative '../tournaments/local_test_tables_test'
include GameRoomTest::Assertions

# These are the actual parent cleanup methods under test, not shared fixtures.
# Import their definitions only; unrelated parent scenarios must not execute.

CleanupProbeStream = Struct.new(:closed, :closes) do
  def initialize; super(false, 0); end
  def gets; "READY\n"; end
  def closed?; closed; end
  def close; self.closes += 1; self.closed = true; end
end

CleanupProbeWaiter = Struct.new(:pid, :joins) do
  def initialize; super(Object.new, []); end
  def alive?; true; end
  def join(seconds = nil)
    joins << seconds
    raise 'original child did not finish' if seconds == 20
    self
  end
end

paths = {
  local_tables: [2, lambda do |primary|
    subject = TournamentLocalTestTablesTest.new
    subject.instance_variable_set(:@directory, 'unused-local-fixture')
    subject.workers(2, '') { raise primary }
  end],
  portable_drafts: [1, lambda do |_primary|
    subject = TournamentDraftsTest.new
    subject.instance_variable_set(:@directory, 'unused-local-fixture')
    subject.test_native_portable_data_path_survives_a_cwd_change
  end],
  parallel_drafts: [3, lambda do |primary|
    subject = TournamentDraftsTest.new
    subject.instance_variable_set(:@directory, 'unused-local-fixture')
    subject.instance_variable_set(:@assertions, 0)
    subject.define_singleton_method(:store) { raise primary }
    subject.test_separate_processes_share_the_stable_lock
  end]
}

paths.each do |name, (count, invoke)|
  children = Array.new(count) { [CleanupProbeStream.new, CleanupProbeStream.new, CleanupProbeWaiter.new] }
  pending, signals, primary = children.dup, [], RuntimeError.new('original scenario failed')
  original_open, original_kill, original_stderr = Open3.method(:popen2e), Process.method(:kill), $stderr
  warnings, error = StringIO.new, nil
  begin
    Open3.define_singleton_method(:popen2e) do |*_, &block|
      owned = pending.shift || raise('Unexpected child creation')
      block ? block.call(*owned) : owned
    end
    Process.define_singleton_method(:kill) do |signal, pid|
      raise 'Unowned signal' unless signal == 'KILL' && children.any? { |child| child.last.pid.equal?(pid) }
      signals << pid
      raise Errno::ESRCH
    end
    $stderr = warnings
    begin
      invoke.call(primary)
    rescue StandardError => observed
      error = observed
    end
  ensure
    Open3.define_singleton_method(:popen2e, original_open)
    Process.define_singleton_method(:kill, original_kill)
    $stderr = original_stderr
  end
  if name == :portable_drafts
    assert(error&.message == 'original child did not finish', "#{name}: primary error was replaced")
  else
    assert(error.equal?(primary), "#{name}: primary error was replaced")
  end
  assert_equal(count, signals.length, "#{name}: later owned children were skipped")
  children.each do |input, output, waiter|
    assert(input.closed? && output.closed?, "#{name}: a pipe remained open")
    assert_equal(1, input.closes)
    assert_equal(1, output.closes)
    assert_equal(name == :portable_drafts ? [20, 5] : [5], waiter.joins,
      "#{name}: cleanup wait must be bounded")
  end
  assert(warnings.string.empty?, "#{name}: an already exited child was treated as failure")
  puts "PASS #{name}: actual parent cleanup, exited-child race, original error, every child and pipe"
end
