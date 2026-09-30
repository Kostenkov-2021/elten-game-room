require_relative "../../lib/table_query_snapshot"
def assert(value, message); raise message unless value; end
now, calls = 0.0, 0
cache = GameRoomTableQuerySnapshot.new(clock: -> { now })
read = -> { calls += 1; [{'username' => 'Alice'}] }
first = cache.fetch(&read)
assert(first.frozen? && first.first.frozen? && first.first['username'].frozen?, 'Snapshot must not share mutable rows')
10.times { assert(cache.fetch(&read).equal?(first), 'Repeated read changed snapshot') }
assert(calls == 1, 'Repeated discovery does not batch')
now = 15
cache.fetch(&read)
assert(calls == 2, 'Remote changes remain bounded by TTL')
cache.invalidate
cache.fetch(&read)
assert(calls == 3, 'Local writes invalidate immediately')
now += 16
begin
  cache.fetch { raise IOError, 'offline' }
  raise 'Failure swallowed'
rescue IOError
end
cache.fetch(&read)
assert(calls == 4, 'Failed refresh must not revive stale cache')
cache.invalidate
2.times { cache.fetch { calls += 1; Array.new(4097) { {'username' => 'Alice'} } } }
assert(calls == 6, 'Oversized query is returned but not retained')
puts 'Bounded table discovery snapshot, TTL, invalidation and errors: OK'
