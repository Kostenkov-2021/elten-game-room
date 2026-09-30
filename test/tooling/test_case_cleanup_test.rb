require 'stringio'
require_relative "../support/cases"
include GameRoomTest::Assertions

cases = GameRoomTest::Cases.new
events = []
body_error, cleanup_error = TypeError.new('original scenario failure'), IOError.new('cleanup failed')
output, diagnostics = StringIO.new, StringIO.new
stdout, stderr = $stdout, $stderr
begin
  $stdout, $stderr = output, diagnostics
  observed = assert_raises(TypeError) do
    cases.run('body and cleanup') do |scenario|
      scenario.cleanup { events << :first }
      scenario.cleanup { events << :second; raise cleanup_error }
      scenario.cleanup { events << :third }
      raise body_error
    end
  end
  assert(observed.equal?(body_error), 'cleanup hid the original scenario failure')
  assert_equal([:third, :second, :first], events, 'failed cleanup abandoned later resources')
  assert(diagnostics.string.include?('cleanup failed') && diagnostics.string.include?('original scenario failure'), 'failure diagnostics were lost')
  events.clear
  observed = assert_raises(IOError) do
    cases.run('cleanup only') do |scenario|
      scenario.cleanup { events << :last }
      scenario.cleanup { raise cleanup_error }
    end
  end
  assert(observed.equal?(cleanup_error), 'cleanup-only failure was swallowed')
  assert_equal([:last], events)
  assert(!output.string.include?('PASS'), 'success was printed before cleanup failed')
  cases.run('next scenario') { events << :next }
  assert_equal([:last, :next], events, 'cleanups leaked into the next scenario')
  assert_equal("PASS next scenario\n", output.string)
ensure
  $stdout, $stderr = stdout, stderr
end
puts 'PASS case cleanup: every resource released, original failure retained, no false success or cross-case leak'
