require_relative '../support/session_runner'
require_relative '../support/assertions'
require_relative '../../games/four_in_a_row'
include GameRoomTest::Assertions

[GameRoomGames::TicTacToe.new, GameRoomGames::FourInARow.new].each do |game|
  h = NativeRoomHarness.new(game: game, users: %w[Alice Bob])
  h.start
  2.times do
    current = h.replay('Alice')
    h.submit(current.current_player, game.legal_actions(current, current.current_player).first)
  end
  runner = runner_for(h, covered: -> { false })
  repository = h.repositories.fetch('Alice')
  calculate = repository.method(:events_revision)
  calls = 0
  repository.define_singleton_method(:events_revision) { |events| calls += 1; calculate.call(events) }
  replay = h.replay('Alice')
  assert(replay.state.nil?, 'exercise a genuine board replay without Hash state')
  source = GameRoomSnapshot.copy(replay.accepted_events)
  replay.accepted_events = source
  session = GameRoomSnapshot.copy(h.session)
  context = GameRoomGames::ActionContext.new(local_data: {'draft' => ['first']})
  publish = lambda do
    runner.publish_view(session: session, replay: replay, busy: false, context: context)
    runner.instance_variable_get(:@view)
  end
  expected = calculate.call(source)
  view = publish.call
  assert_equal(expected, view[:revision].to_legacy)
  20.times { publish.call }
  assert_equal(1, calls, 'idle publication rescanned the accepted history')
  assert(!source.frozen? && !source.first.frozen? && !source.first['value'].frozen?, 'publication froze its producer')
  assert(!replay.board.frozen? && !replay.players.frozen?, 'publication froze the mutable model')
  assert_raises(FrozenError) { replay.accepted_events << {} }
  assert_raises(FrozenError) { replay.accepted_events.first['__id'] = 999 }
  assert_raises(FrozenError) { replay.accepted_events.first['value'].replace('changed') }
  source.first['value'].replace('outside mutation')
  assert(replay.accepted_events.first['value'] != source.first['value'], 'published history aliases its producer')

  # Busy state and local input still change on every publication, without a move.
  context.local_data['draft'][0].replace('second')
  runner.publish_view(session: session, replay: replay, busy: true, context: context)
  updated = runner.instance_variable_get(:@view)
  assert(updated[:busy], 'cached revision swallowed busy state')
  assert_equal(['second'], updated[:local_data]['draft'])
  context.local_data['draft'][0].replace('third')
  assert_equal(['second'], updated[:local_data]['draft'], 'published input aliases the UI')
  assert_equal(['first'], view[:local_data]['draft'], 'new publication mutated its predecessor')
  assert_equal(1, calls)

  # A corrected prefix with the same count/last ID is a new snapshot even if
  # the legacy revision pair happens to remain the same.
  replay.accepted_events = GameRoomSnapshot.copy(replay.accepted_events)
  replay.accepted_events.first['value'].replace('corrected prefix')
  assert_equal(expected, publish.call[:revision].to_legacy)
  assert_equal(2, calls, 'corrected prefix reused the previous snapshot')
  replay.accepted_events = GameRoomSnapshot.copy(replay.accepted_events)
  replay.accepted_events.first['__id'] = expected.last + 100
  assert_equal([2, expected.last + 100], publish.call[:revision].to_legacy)
  assert_equal(3, calls, 'changed earlier ID was ignored')

  # A copied replay loses Ruby frozen flags. It must acquire a new owned log;
  # neither Marshal nor reuse of the same Replay object may retain a token.
  replay = GameRoomSnapshot.copy(replay)
  replay.accepted_events.first['__id'] += 1
  assert_equal([2, expected.last + 101], publish.call[:revision].to_legacy)
  assert_equal(4, calls)
  session['__id'] = 2
  publish.call
  session['__id'] = 1 # Random match IDs need not increase.
  publish.call
  session['__control_epoch'] = +'epoch-a'
  publish.call
  session['__control_epoch'].replace('epoch-b')
  publish.call
  session['table_id'] = session['table_id'].to_i + 1
  publish.call
  assert_equal(9, calls, 'session/table/control epoch reused a foreign revision')
  runner.close
end

# The cached UI acknowledgement is never substituted for commit validation.
h = NativeRoomHarness.new(game: GameRoomGames::TicTacToe.new, users: %w[Alice Bob])
h.start
runner = runner_for(h, covered: -> { false })
old_session = GameRoomSnapshot.copy(h.session)
old = h.replay('Alice')
runner.publish_view(session: h.session, replay: old, busy: false, context: GameRoomGames::ActionContext.new)
2.times do
  current = h.replay('Alice')
  h.submit(current.current_player, h.game.legal_actions(current, current.current_player).first)
end
model = runner.instance_variable_get(:@game)
model.define_singleton_method(:action_for) { |*args, **options| raise 'stale view reached action_for' }
assert_raises(GameRoomSessionRunner::StaleView) do
  h.as('Alice') { runner.submit(session: h.session, replay: old, selection: {'x' => 2, 'y' => 2}, actor: 'Alice') }
end
assert_equal(2, h.events('Alice').length, 'obsolete publication wrote a move')
h.start
assert_raises(GameRoomSessionRunner::StaleView) do
  h.as('Alice') { runner.submit(session: old_session, replay: old, selection: {}, actor: 'Alice') }
end
assert(h.events('Alice').empty?, 'previous match wrote into a rematch')
runner.close

# Actual private-answer capture is refreshed even when its event log is stable.
game = GameRoomGames::Categories.new
h = NativeRoomHarness.new(game: game, users: %w[Alice Bob])
h.start
runner = runner_for(h)
step(h, runner, count: 3)
replay = h.replay('Alice')
surface = GameRoomSessionRunner::CapturedSurface.new({'answers' => {'country' => 'first'}})
context = GameRoomGames::ActionContext.new
runner.publish_view(session: h.session, replay: replay, busy: true, context: context, surface: surface)
first = runner.instance_variable_get(:@view)
surface.submission_action['answers']['country'].replace('second')
runner.publish_view(session: h.session, replay: replay, busy: false, context: context, surface: surface)
second = runner.instance_variable_get(:@view)
assert(!second[:busy] && first[:busy], 'publication did not release presentation')
assert_equal('first', first[:surface].submission_action['answers']['country'])
assert_equal('second', second[:surface].submission_action['answers']['country'])
assert_equal(first[:surface_identity], second[:surface_identity])
runner.close
puts 'PASS publication revision: immutable owned prefix, idle cost, nil-state boards, corrections, copied replay, session/epoch, fresh commit validation and live drafts'
