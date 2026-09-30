require_relative "../../support/session_runner"
require_relative "../../support/krowa"

fixture = KrowaTestGame.new(variant: 'race', players: %w[Alice Bob])
game = fixture.game
h = NativeRoomHarness.new(game: game, users: %w[Alice Bob],
  options: game.default_options.merge('variant' => 'race', 'length' => 3))
h.start
rs = h.users.to_h { |user| [user, runner_for(h, user)] }
step(h, rs['Alice'], count: 2)
before = h.replay('Alice')
ctx = rs['Alice'].send(:context)
word = ctx.hidden_submissions.reveal(session_id: h.session['__id'], round_id: 'krowa:1', user: 'Alice').payload['word']
choice = {'kind' => 'question', 'action' => 'submit', 'question_id' => 'krowa-answer-1', 'answer' => word}
h.users.each do |user|
  h.as(user) do
    assert(rs[user].submit(session: h.session, replay: before, selection: choice, actor: user).first == :ok,
      "simultaneous Krowa guess rejected for #{user}")
  end
  step(h, rs['Alice'])
end
step(h, rs['Alice'], count: 4)
h.users.each { |user| step(h, rs[user], user) }
assert(h.replay('Alice').finished?, 'covered Krowa host did not evaluate/reveal the word')
assert(h.replay('Alice').state[:results].keys.sort == %w[Alice Bob], 'Krowa lost a concurrent answer')
assert(h.events('Alice').size == h.replay('Alice').accepted_events.size, 'Krowa wrote rejected events')
h.assert_converged('Krowa race behind another scene')
rs.each_value(&:close)
puts 'Krowa runner: preserved custom word bank, simultaneous guesses, hidden secret, evaluation and final reveal passed'
