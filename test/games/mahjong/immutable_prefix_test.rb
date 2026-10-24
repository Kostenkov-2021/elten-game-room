require_relative '../../support/session_runner'
require_relative '../../../games/mahjong'
include GameRoomTest::Assertions

game = GameRoomGames::Mahjong.new
h = NativeRoomHarness.new(game: game, users: ['Alice'], bots: 3,
  options: game.normalize_options('variant'=>'hong_kong', 'hong_kong_winds'=>'4', 'bot_delay'=>0))
h.start
h.submit('Alice')
repo = h.repositories['Alice']
snapshot = repo.snapshot_for(h.session, read_only: true)
calls = 0
trace = TracePoint.new(:call) { |c| calls += 1 if c.self.equal?(repo) && c.method_id == :actor_of }
first = trace.enable { game.replay(snapshot.session, snapshot.events, repo) }
assert_equal(1, calls)
trace.enable { 20.times { game.replay(snapshot.session, snapshot.events, repo) } }
assert_equal(1, calls, 'Unchanged authenticated input rechecked old immutable records')
assert(first.history.frozen? && first.accepted_events.frozen?)
copy = GameRoomSnapshot.copy(first)
assert(copy.history.equal?(first.history) && copy.accepted_events.equal?(first.accepted_events))
assert(!copy.state.equal?(first.state), 'Current-hand state was shared with a caller')
original_actor = repo.method(:actor_of)
repo.define_singleton_method(:actor_of) { |_event, _session=nil| 'Bob' }
changed = game.replay(snapshot.session, snapshot.events, repo)
assert_equal([], changed.accepted_events, 'Changed actor implementation reused an old authenticated prefix')
repo.define_singleton_method(:actor_of, original_actor)
restored = game.replay(snapshot.session, snapshot.events, repo)
assert_equal(first.accepted_events, restored.accepted_events)

mutable = repo.snapshot_for(h.session)
mutable.events.first['value'] = '{invalid'
bad = game.replay(mutable.session, mutable.events, repo)
assert_equal([], bad.accepted_events, 'Changed mutable input reused the immutable fast path')
again = game.replay(snapshot.session, snapshot.events, repo)
assert_equal(first.accepted_events, again.accepted_events)
puts 'PASS Mahjong immutable native prefix: unchanged auth, isolated current hand, shared sealed logs, changed method and corrected earlier input'
