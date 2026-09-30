def _(text)
  text
end

require_relative "../../lib/game_teams"
require_relative "../../games/base"

def assert(condition, message)
  raise message if !condition
end

four = ["Alice", "Bob", "Carol", "Dave"]
pairs = GameRoomTeams::Assignment.new(players: four, team_size: 2)
assert(pairs.seats == [0, 1, 0, 1], "four-player teams were not assigned alternately")
assert(pairs.members_for("team:0") == ["Alice", "Carol"], "the first automatic pair is incorrect")
assert(pairs.members_for("team:1") == ["Bob", "Dave"], "the second automatic pair is incorrect")
assert(pairs.valid?, "the automatic four-player assignment is invalid")

pairs.assign(1, 0)
assert(!pairs.valid?, "an overfilled team was accepted")
assert(pairs.validation_error.include?("Team 1"), "team validation did not identify the invalid team")
pairs.assign(2, 1)
assert(pairs.valid?, "a manually swapped pair was rejected")
assert(pairs.members_for(0) == ["Alice", "Bob"], "a manual team selection was not retained")
assert(pairs.team_number_for("bob") == 1, "team lookup is not case-insensitive")

six = ["Alice", "Bob", "Carol", "Dave", "Eve", "Frank"]
six_pairs = GameRoomTeams::Assignment.new(players: six, team_size: 2)
assert(six_pairs.seats == [0, 1, 2, 0, 1, 2], "three automatic pairs are incorrect")
six_triples = GameRoomTeams::Assignment.new(players: six, team_size: 3)
assert(six_triples.seats == [0, 1, 0, 1, 0, 1], "two automatic triples are incorrect")

class TeamContractGame < GameRoomGames::Base
  def team_size(_options, player_count:)
    player_count == 4 ? 2 : 0
  end
end

game = TeamContractGame.new
stored = game.with_team_assignment({}, players: four, seats: [0, 0, 1, 1])
assert(stored[GameRoomTeams::OPTION_KEY] == [0, 0, 1, 1], "the shared game contract lost team seats")
restored = game.team_assignment(JSON.parse(JSON.generate(stored)), players: four)
assert(restored.members_for(0) == ["Alice", "Bob"], "saved teams were not restored from session JSON")

puts "Team assignment framework tests passed"

moved = GameRoomTeams::Assignment.new(players: four, team_size: 2)
assert(moved.move(0, -1) == 0 && moved.players == four, 'team move wraps at top')
assert(moved.move(1, 1) == 2 && moved.players == %w[Alice Carol Bob Dave], 'move did not follow person')
assert(moved.seats == [0, 1, 0, 1] && moved.valid?, 'moving changed the seat layout or team sizes')
assert(moved.seats_for(four) == [0, 0, 1, 1], 'moved seats not mapped back to original game order')
assert(moved.move(3, 1) == 3, 'team move wraps at bottom')
moved.reset
assert(moved.players == four && moved.seats == [0, 1, 0, 1], 'automatic assignment does not reset order')

assert(stored['team_players'] == four, 'saved teams have no identities')
assert(game.prepared_team_assignment(stored, players: four.reverse).members_for(0) == %w[Alice Bob], 'roster order changed partnerships')
remapped = game.options_for_team_roster(stored, players: four.reverse)
assert(remapped['team_seats'] == [1, 1, 0, 0] && remapped['team_players'] == four.reverse, 'team indices not remapped for next match')
assert(!game.prepared_team_assignment(stored, players: %w[Alice Bob Carol Eve]), 'replacement inherited someone else team')
assert(!game.options_for_team_roster(stored, players: %w[Alice Bob Carol Eve]).key?('team_seats'), 'stale team seats survived roster change')
[[9, 9, 9, 9], [0, 0, 0, 1], [], [0, 1], ['a', 'a', 1, 1], [0.1, 0.2, 1, 1]].each do |bad|
  assert(!game.prepared_team_assignment(stored.merge('team_seats' => bad), players: four), 'invalid saved team accepted')
end
choices = 20.times.map do |seed|
  moved.randomize(random: Random.new(seed))
  assert(moved.valid? && moved.players.sort == four.sort, 'random teams lose people or have invalid sizes')
  moved.seats_for(four)
end
assert(choices.uniq.length > 1, 'random teams always use the same assignment')
