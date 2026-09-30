require_relative "../support/game_session_runner_deadline"
require_relative "../../games/scrabble"
require_relative "../../games/taboo"

# Games intentionally without bots still need an independent dealer/timer.
scrabble = GameRoomGames::Scrabble.new
h = NativeRoomHarness.new(game: scrabble, users: %w[Alice Bob],
  options: scrabble.default_options.merge('thinking_time' => 20))
h.start
r = runner_for(h)
clock = RunnerTestClock.new(Time.now.to_i)
r.instance_variable_set(:@clock, clock)
step(h, r, count: 2)
assert(h.replay('Alice').state[:phase] == :playing, 'covered Scrabble did not deal')
actor = h.replay('Alice').current_player
hand = h.replay('Alice').state[:racks][actor].dup
clock.value += 30
step(h, r)
assert(h.replay('Alice').current_player != actor, 'covered Scrabble did not pass at its deadline')
assert(h.replay('Alice').state[:racks][actor] == hand, 'Scrabble timer played a human tile')
assert(h.replay('Alice').accepted_events.size == h.events('Alice').size, 'Scrabble timeout was rejected')
h.assert_converged('covered Scrabble timeout')
r.close

taboo = GameRoomGames::Taboo.new
h = NativeRoomHarness.new(game: taboo, users: %w[Alice Bob Carol Dave])
h.start
r = runner_for(h)
clock = RunnerTestClock.new(Time.now.to_i)
r.instance_variable_set(:@clock, clock)
step(h, r, count: 2)
current = h.replay('Alice')
assert(current.state[:phase] == :ready, 'covered Taboo did not deal')
giver = current.current_player
# Starting to describe is deliberately human; the runner must not start it.
step(h, r, count: 20)
assert(h.replay('Alice').state[:phase] == :ready, 'Taboo started describing without a person')
h.submit(giver, {'action' => 'start', 'token' => taboo.token(current.state)},
  context: GameRoomGames::ActionContext.new(now: clock.value, table_owner: 'Alice'))
step(h, r)
clock.value += 10
step(h, r)
assert(h.replay('Alice').state[:phase] == :describing, 'covered Taboo missed preparation deadline')
clock.value += 100
step(h, r)
assert(h.replay('Alice').state[:phase] == :review, 'covered Taboo missed end of describing')
step(h, r, count: 20)
assert(h.replay('Alice').state[:phase] == :review, 'runner approved Taboo review for a person')
assert(h.replay('Alice').accepted_events.size == h.events('Alice').size, 'Taboo automatic action was rejected')
h.assert_converged('covered Taboo preparation and timeout')
r.close
puts 'Human-only games: Scrabble and Taboo deal/deadline policies, no automated human choices passed'
