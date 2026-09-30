require_relative "../support/game_session_runner_deadline"

[GameRoomGames::Uno.new, GameRoomGames::Makao.new, GameRoomGames::Poker.new].each do |game|
  h = NativeRoomHarness.new(game: game, users: %w[Alice Bob], options: game.default_options.merge('thinking_time' => 3))
  h.start
  r = runner_for(h)
  clock = RunnerTestClock.new(Time.now.to_i)
  r.instance_variable_set(:@clock, clock)
  step(h, r, count: 6)
  before = h.events('Alice').length
  clock.value += 10
  step(h, r)
  after = h.events('Alice')
  assert(after.length > before, "#{game.id} lost the deadline without UI")
  assert(after.last['action'].match?(/timeout/), "#{game.id} played a human card instead of its timeout policy: #{after.last}")
  h.assert_converged("#{game.id} deadline")
  5.times { step(h, r) }
  # Same clock + the newly established deadline must not repeat the penalty.
  assert(h.events('Alice').length <= after.length + 1, "#{game.id} repeated timeout without advancing its clock")
  r.close
end

# A Categories draft captured on the UI thread is committed/revealed normally
# behind another scene, never borrowed by the next round.
game = GameRoomGames::Categories.new
h = NativeRoomHarness.new(game: game, users: %w[Alice Bob], options: game.default_options)
h.start
rs = h.users.to_h { |u| [u, runner_for(h, u)] }
clocks = rs.to_h do |u, runner|
  clock = RunnerTestClock.new(Time.now.to_i)
  runner.instance_variable_set(:@clock, clock)
  [u, clock]
end
step(h, rs['Alice'], count: 3)
before = h.replay('Bob')
round = before.state[:round]
surface = GameRoomSessionRunner::CapturedSurface.new({'kind' => 'answer_sheet', 'action' => 'submit', 'answers' => {'country' => 'A test answer'}})
rs['Bob'].publish_view(session: h.session, replay: before, busy: false,
  context: GameRoomGames::ActionContext.new, surface: surface)
clocks.each_value { |c| c.value += 1000 }
step(h, rs['Bob'], 'Bob')
assert(h.replay('Bob').state[:commitments].key?('Bob'), 'covered guest did not commit its captured answers')
step(h, rs['Alice'], count: 3)
step(h, rs['Bob'], 'Bob', count: 3)
assert(h.replay('Bob').state[:reveals].key?('Bob'), 'covered guest did not reveal its own committed answer')
h.assert_converged('hidden answer deadline')
rs.each_value(&:close)

# Real quiz policy: category selection, both private commitments/reveals,
# scoring and the preparation pause leading to the next question.
game = GameRoomGames::QuizParty.new
h = NativeRoomHarness.new(game: game, users: %w[Alice Bob])
h.start
rs = h.users.to_h { |u| [u, runner_for(h, u)] }
clocks = rs.to_h do |u, runner|
  clock = RunnerTestClock.new(Time.now.to_i)
  runner.instance_variable_set(:@clock, clock)
  [u, clock]
end
phases = []
30.times do
  h.users.each do |u|
    step(h, rs[u], u)
    current = h.replay(u)
    phases << current.state[:phase]
    ctx = rs[u].send(:context)
    choices = game.legal_actions(current, u, context: ctx)
    # These are deliberate human inputs; the worker itself must never select
    # answers or categories on behalf of a person.
    if !choices.empty? && [:choosing, :category, :choosing_category, :answering].include?(current.state[:phase])
      h.as(u) { rs[u].submit(session: h.session, replay: current, selection: choices.first, actor: u) }
    end
  end
  clocks.each_value { |c| c.value += 2 }
  break if h.events('Alice').count { |e| e['action'] == 'question_finished' } >= 3
end
actions = h.events('Alice').map { |event| event['action'] }
assert(actions.count('answer_commit') >= 4, "quiz did not progress through multiple questions: #{actions}, #{phases.uniq}")
assert(actions.count('answer_nonce') >= 6 && actions.count('answer_pick') >= 6, "quiz did not reveal both players: #{actions}")
assert(h.replay('Alice').accepted_events.size == actions.size, 'quiz emitted rejected events')
h.assert_converged('quiz multiple rounds behind UI')
rs.each_value(&:close)

puts 'Runner deadlines: UNO, Makao, Poker, Categories and three complete Quiz questions passed'
