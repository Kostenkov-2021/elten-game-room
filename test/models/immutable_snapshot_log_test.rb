require_relative '../support/cases'
require_relative '../../lib/game_snapshot'
include GameRoomTest::Assertions

cases = GameRoomTest::Cases.new
cases.run('only owned, recursively sealed log data is shared') do
  rows = [{'value'=>'first', 'nested'=>[['second']]}]
  log = GameRoomSnapshot::Log.from_owned(rows)
  assert(log.frozen? && log.first.frozen? && log.first['nested'].first.first.frozen?)
  source = {history: log, state: ['mutable']}
  copy = GameRoomSnapshot.copy(source)
  assert(copy[:history].equal?(log))
  copy[:state].first.replace('changed')
  assert_equal('mutable', source[:state].first)
  assert_raises(FrozenError) { log.first['value'].replace('changed') }
  source[:history] = []
  assert_equal(1, copy[:history].length)
end
cases.run('large logs are references only inside their bounded capture') do
  log = GameRoomSnapshot::Log.from_owned(Array.new(5000) { |i| {'id'=>i, 'value'=>'a recording of an old move'} })
  capture = GameRoomSnapshot.capture([log, log, ['mutable']])
  assert(capture.instance_variable_get(:@encoded).bytesize < 200, 'Capture serialized the whole old log')
  assert(capture.bytesize >= log.retained_bytes, 'Memory budget omitted the retained log')
  copied = capture.restore
  assert(copied[0].equal?(log) && copied[1].equal?(log))
  normal = Marshal.load(Marshal.dump(log))
  assert_equal(log, normal)
  assert(!normal.equal?(log) && normal.frozen? && normal.first.frozen?, 'Standalone Marshal kept an external reference')
  assert_raises(TypeError) { GameRoomSnapshot::Log._load('R0') }
end
cases.run('failed and nested copies restore the previous per-thread context') do
  log = GameRoomSnapshot::Log.from_owned([{'value'=>'one'}])
  assert_raises(TypeError) { GameRoomSnapshot.copy([log, -> {}]) }
  assert_equal(nil, Thread.current[GameRoomSnapshot::CONTEXT_KEY])
  assert(GameRoomSnapshot.copy(log).equal?(log))
  other = Thread.new { GameRoomSnapshot.copy(log) }.value
  assert(other.equal?(log))
  assert_equal(nil, Thread.current[GameRoomSnapshot::CONTEXT_KEY])
end
cases.run('an appended log keeps its sealed prefix but owns the new container') do
  previous = GameRoomSnapshot::Log.from_owned([{'value'=>'one'}])
  values = previous.dup
  values << {'value'=>'two'}
  following = GameRoomSnapshot::Log.from_owned(values, previous: previous)
  assert(!following.equal?(previous) && following.first.equal?(previous.first))
  assert_equal(1, previous.length)
  assert_equal(2, following.length)
  assert(following.last.frozen? && following.last['value'].frozen?)
end
