require_relative '../support/new_games_fixture'
require_relative '../../games/scrabble'
require_relative '../../lib/tournaments/game_result'
require_relative '../../lib/tournaments/standings'
require 'digest'

class ScrabblePlacementRandom
  Result = Struct.new(:values)
  def initialize(seed); @seed = seed; end
  def roll(count:, sides:)
    raise 'Unexpected random request' unless count == 16 && sides == 256
    Result.new([@seed.to_s(16).rjust(32, '0')].pack('H*').bytes.map { |v| v + 1 })
  end
end

fixture = JSON.parse(File.read(File.join(__dir__, '../fixtures/scrabble-placement-history.json')))
game = GameRoomGames::Scrabble.new
players = fixture.fetch('scores').keys
options = game.normalize_options(fixture.fetch('options'))
session = {'options' => JSON.generate(options)}
repository = NewGames116Repository.new(players)
random = ScrabblePlacementRandom.new(fixture.fetch('seed'))
events = []
replay = game.replay(session, events, repository)
fixture.fetch('moves').each_with_index do |move, index|
  context = GameRoomGames::ActionContext.new(random_source: random, now: 1_800_000_000 + index)
  replay = append_action(game, session, repository, events, replay,
    move.fetch('actor'), move.fetch('selection'), context)
  assert(replay.accepted_events == events, 'An ordinary Scrabble move was rejected')
end
assert(replay.finished? && replay.state[:bag].size <= 7, 'Complete ordinary-bag fixture did not finish')
assert(game.tiles(replay.state).size == 100, 'Fixture no longer uses the ordinary English tile bag')
assert(game.participant_scores(replay) == fixture.fetch('scores'), 'Final adjusted scores changed')
assert(events.size == fixture.fetch('event_count') && Digest::SHA256.hexdigest(JSON.generate(events)) == fixture.fetch('wire_sha256'),
  'Complete accepted history changed')
arguments = {game: game, replay: replay, players: players.map { |p| {'username'=>p, 'account'=>p.downcase} },
  options: options, event_count: events.size, events: events}
type = GameRoomTournaments::GameResult
%w[game-owned-scores-v1 game-owned-result-v2 game-owned-result-v3
  game-owned-result-v4 game-owned-result-v5 game-owned-result-v6].each do |policy|
  expected = fixture.fetch('exported').dup
  expected['score_order'] = 'higher' if %w[game-owned-result-v4 game-owned-result-v5].include?(policy)
  assert(type.from_replay(**arguments, result_policy: policy) == expected, "Historical Scrabble #{policy} changed")
end
before = Marshal.dump(replay.state)
summary = type.from_replay(**arguments, result_policy: type::CURRENT_RESULT_POLICY)
assert(!summary['draw'] && summary['winners'] == %w[bob dorota], 'Shared Scrabble leaders still become a whole-table draw')
assert(summary['places'] == [%w[bob dorota], ['carol'], ['alice']], 'Adjusted-score finishing places lost')
assert(summary['scores'].nil? && !summary.key?('score_order'), 'Finishing places enabled numeric small points')
rows = GameRoomTournaments::Standings.calculate(units: players.map(&:downcase),
  results: [summary.slice('participants', 'winners', 'scores', 'score_order', 'places').merge('id'=>'scrabble')],
  points: GameRoomTournaments::Standings::MATCH_POINTS)
assert(rows.to_h { |row| [row['unit'], row['points']] } == {'bob'=>5, 'dorota'=>5, 'carol'=>2, 'alice'=>0},
  'Shared-first-place match points changed')
assert(Marshal.dump(replay.state) == before, 'Result export changed the completed game')
puts 'PASS complete accepted ordinary Scrabble history: shared first place, lower places, disabled small points and exact v1-v6 summaries'
