require_relative '../../support/session_runner'
require_relative '../../../games/axel_pong'

warnings = []
Log.define_singleton_method(:warning) { |message| warnings << message }
game = GameRoomGames::AxelPong.new
h = NativeRoomHarness.new(game: game, users: %w[Alice Bob])
h.start
runner = runner_for(h)
begin
  initial = h.replay('Alice')
  context = GameRoomGames::ActionContext.new(local_data: {'pong_point' => '0:0'})
  runner.publish_view(session: h.session, replay: initial, busy: false, context: context)
  step(h, runner)
  assert(h.replay('Alice').state[:scores] == [1, 0], 'First agreed point was not saved')

  # Native delivery can reach the worker before the covered UI consumes the
  # durable point. The previous UI snapshot is not another pending point.
  step(h, runner, count: 5)
  assert(warnings.empty?, "Stale confirmed point was resubmitted: #{warnings.inspect}")
  assert(h.replay('Alice').state[:scores] == [1, 0], 'Confirmed point duplicated')

  current = h.replay('Alice')
  context.local_data = {'pong_point' => '1:1'}
  runner.publish_view(session: h.session, replay: current, busy: false, context: context)
  step(h, runner)
  assert(h.replay('Alice').state[:scores] == [1, 1], 'Next point was delayed or rejected')
  step(h, runner, count: 5)
  assert(warnings.empty?, 'Second point triggered an invalid retry')

  replay = h.replay('Alice')
  [nil, 7, '1:0', '3:0', '2:2', '2:1:invalid'].each do |point|
    context.local_data = {'pong_point' => point}
    assert(game.automatic_action(replay, 'Alice', context: context).nil?, 'Invalid snapshot selected an action')
  end
  %w[2:0 2:1 2:1:timeout].each do |point|
    context.local_data = {'pong_point' => point}
    selection = game.automatic_action(replay, 'Alice', context: context)
    assert(selection && selection['point'] == point, 'Valid pending point was suppressed')
  end
  puts 'PASS Pong runner: stale confirmed UI point is not retried; next point and timeout remain available'
ensure
  runner.close
end
