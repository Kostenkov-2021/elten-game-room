require 'stringio'
require_relative '../support/owned_process_cleanup'
require_relative '../support/assertions'
include GameRoomTest::Assertions

ScopeCleanupReader = Struct.new(:failure, :joins) do
  def initialize(failure = nil); super(failure, []); end
  def alive?; false; end
  def join(seconds)
    joins << seconds
    raise failure if failure
    self
  end
end

previous_stderr, warnings = $stderr, StringIO.new
$stderr = warnings
begin
  reader = ScopeCleanupReader.new
  assert_equal(:result, GameRoomTest::OwnedProcessCleanup.run([], reader_threads: [reader]) { :result })
  assert_equal([5], reader.joins)
  cleanup_failure = IOError.new('scope cleanup failed')
  begin
    raise ArgumentError, 'unrelated caller rescue'
  rescue ArgumentError
    reader = ScopeCleanupReader.new(cleanup_failure)
    observed = assert_raises(IOError) do
      GameRoomTest::OwnedProcessCleanup.run([], reader_threads: [reader]) { :result }
    end
    assert(observed.equal?(cleanup_failure), 'Caller context hid or replaced the cleanup-only failure')
    assert_equal([5], reader.joins)
  end
  fatal_type = Class.new(Exception)
  primary = fatal_type.new('original nonstandard body failure')
  reader = ScopeCleanupReader.new(cleanup_failure)
  observed = assert_raises(fatal_type) do
    GameRoomTest::OwnedProcessCleanup.run([], reader_threads: [reader]) { raise primary }
  end
  assert(observed.equal?(primary), 'Cleanup replaced a non-StandardError primary')
  assert_equal([5], reader.joins)
  reader = ScopeCleanupReader.new
  assert_equal(:escaped, catch(:scope_exit) do
    GameRoomTest::OwnedProcessCleanup.run([], reader_threads: [reader]) { throw :scope_exit, :escaped }
  end)
  assert_equal([5], reader.joins)
  assert_equal(2, warnings.string.scan('scope cleanup failed').length, 'Secondary cleanup failures lost diagnostics')
ensure
  $stderr = previous_stderr
end
puts 'PASS owned process scope: return, actual body error ownership, unrelated rescue, nonstandard Exception and nonlocal exit; fake readers only'
