require_relative 'support/farkle'

# Independent exhaustive oracle: partition a roll into the scoring groups
# specified in our rules, without sharing the production score function.
groups = [[[1], 10], [[5], 5]]
(1..6).each do |face|
  groups << [[face] * 3, face == 1 ? 75 : face * 10]
  groups << [[face] * 4, 100 + face * 10]
  groups << [[face] * 5, 300 + face * 20]
  groups << [[face] * 6, 600 + face * 25]
end
groups.concat([[[1,2,3,4,5],100], [[2,3,4,5,6],100], [[1,2,3,4,5,6],200]])
(1..6).to_a.combination(3) { |a| groups << [a.flat_map { |n| [n,n] }, 150] }
(1..6).to_a.combination(2) { |a,b| groups << [[a,a,a,b,b,b],250] }
(1..6).each { |a| (1..6).each { |b| groups << [[a,a,a,a,b,b],250] if a != b } }
memo = {[] => 0}
oracle = lambda do |dice|
  dice = dice.sort
  return memo[dice] if memo.key?(dice)
  memo[dice] = groups.filter_map do |values, points|
    rest = dice.dup
    next unless values.all? { |value| (i = rest.index(value)) && rest.delete_at(i) }
    remainder = oracle.call(rest)
    remainder && points + remainder
  end.max
end
game = GameRoomGames::Farkle.new
checked = 0
(1..6).each do |count|
  (1..6).to_a.repeated_combination(count).each do |dice|
    checked += 1
    assert(game.score_selection(dice) == oracle.call(dice), "Incorrect partition: #{dice}")
  end
end
assert(checked == 923, 'Incomplete roll coverage')
repository = FarkleRepository.new(%w[Alice Bob])
session = {'options' => JSON.generate(game.new_game_options({}))}
[[[1,1,2,3,4,5],110], [[1,2,3,4,5,5],105], [[2,3,4,5,5,6],105]].each do |dice, points|
  events = [farkle_event(1, 'Alice', 'roll', dice.join(','))]
  replay = game.replay(session, events, repository)
  action = game.legal_actions(replay, 'Alice').find { |a| a['indices'].to_s.split(',').length == 6 }
  assert(action, 'Bot/UI cannot select the full scoring roll')
  status, plan = game.action_for(action, replay, 'Alice')
  assert(status == :ok, 'Full scoring selection rejected')
  plan.events.each { |event| events << farkle_event(events.length + 1, 'Alice', event.action, event.value) }
  replay = game.replay(session, events, repository)
  assert(replay.state[:turn_points] == points && replay.state[:dice_to_roll] == 6, 'Incorrect score or hot dice')
  assert(replay.state[:phase] == :awaiting_roll && replay.current_player == 'Alice', 'Full selection lost the turn')
  events << farkle_event(events.length + 1, 'Alice', 'roll', '1,2,2,3,4,6')
  assert(game.replay(session, events, repository).state[:phase] == :selecting, 'Cannot roll after hot dice')
end
puts 'PASS Farkle: 923 partitions and three full selections/hot-dice continuations'
