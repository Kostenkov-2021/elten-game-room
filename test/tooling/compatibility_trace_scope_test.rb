require_relative '../support/assertions'
require_relative '../support/ft2_compatibility_trace'
include GameRoomTest::Assertions

trace = FT2CompatibilityTrace.new
begin
  result = trace.during('outer') do
    FT2CompatibilityTrace.marker
    entered = false
    assert_raises(RuntimeError) { trace.during('inner') { entered = true } }
    assert_equal(false, entered, 'A rejected nested measurement ran its body')
    FT2CompatibilityTrace.marker
    trace.worker { FT2CompatibilityTrace.marker }
    :result
  end
  assert_equal(:result, result)
  assert_equal(['outer'] * 3, trace.rows.map { |row| row.fetch('phase') },
    'Rejecting a nested measurement disabled its still-active outer measurement')
  assert_equal(['marker'] * 3, trace.rows.map { |row| row.fetch('method') })
  assert_equal(2, trace.rows.map { |row| row.fetch('thread') }.uniq.length)
  FT2CompatibilityTrace.marker
  assert_equal(3, trace.rows.length, 'A completed scope kept recording')

  failure = ArgumentError.new('measurement body failed')
  observed = assert_raises(ArgumentError) { trace.during('failed') { raise failure } }
  assert(observed.equal?(failure), 'Measurement cleanup replaced the original body failure')
  FT2CompatibilityTrace.marker
  assert_equal(3, trace.rows.length, 'An exceptional scope kept recording')

  assert_equal(:escaped, catch(:trace_exit) do
    trace.during('escaped') { throw :trace_exit, :escaped }
  end)
  FT2CompatibilityTrace.marker
  assert_equal(3, trace.rows.length, 'A nonlocal exit kept recording')
  trace.during('next') { FT2CompatibilityTrace.marker }
  assert_equal('next', trace.rows.last.fetch('phase'))
ensure
  trace.close
end
puts 'PASS compatibility trace scope: rejected nesting preserves the outer main/worker observation; return, exception and nonlocal exits release it'
