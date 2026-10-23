require_relative '../support/new_games_fixture'
require_relative '../../games/war'
require_relative '../../lib/tournaments/game_result'
require_relative '../../lib/tournaments/standings'
require 'digest'

game = GameRoomGames::War.new
type = GameRoomTournaments::GameResult
build = lambda do |names, seed|
  options = game.normalize_options('deck'=>'short', 'battle_limit'=>20)
  session = {'options'=>JSON.generate(options)}
  repository = NewGames116Repository.new(names)
  events = []
  replay = game.replay(session, events, repository)
  random = GameRoomRandom::SeededSource.new(seed)
  1_000.times do
    break if replay.finished?
    actor = game.active_actors(replay).first || names.first
    context = GameRoomGames::ActionContext.new(random_source:random, now:1_800_000_000 + events.size)
    selection = game.automatic_action(replay, names.first, context:context) ||
      game.legal_actions(replay, actor, context:context).first
    assert(selection, 'A normal complete War history stalled')
    actor = names.first if selection['action'] == 'deal'
    replay = append_action(game, session, repository, events, replay, actor, selection, context)
    assert(replay.accepted_events == events, 'A normally generated War action was rejected')
  end
  assert(replay.finished?, 'The complete ordinary War match did not finish')
  cold = game.replay(session, JSON.parse(JSON.generate(events)), repository)
  assert(cold.state == replay.state && cold.accepted_events == events, 'Cold War replay changed')
  counts = names.to_h { |name| [name, replay.state[:piles].fetch(name).size] }
  assert(counts.values.sum + replay.state[:carried].size == 24, 'War lost a physical card')
  {game:game, replay:replay, players:names.map { |name| {'username'=>name, 'account'=>name.downcase} },
    options:options, events:events, event_count:events.size}
end

arguments = build.call(%w[Alice Bob Carol], 11)
assert(arguments[:replay].state[:piles].transform_values(&:size) == {'Alice'=>12, 'Bob'=>12, 'Carol'=>0},
  'The complete shared-first War route changed')
assert(arguments[:event_count] == 58 && Digest::SHA256.hexdigest(JSON.generate(arguments[:events])) ==
  '855d5b02aa7c1be7fc74eb302913deb16d687201ccaee72c77190d485a4a719f', 'The accepted ordinary wire history changed')

legacy = {'participants'=>%w[alice bob carol], 'winners'=>[], 'draw'=>true, 'scores'=>nil, 'event_count'=>58}
%w[game-owned-scores-v1 game-owned-result-v2 game-owned-result-v3
  game-owned-result-v4 game-owned-result-v5 game-owned-result-v6].each do |policy|
  expected = legacy.dup
  expected['score_order'] = 'higher' if %w[game-owned-result-v4 game-owned-result-v5].include?(policy)
  assert(type.from_replay(**arguments, result_policy:policy) == expected, "Historical War #{policy} changed")
end

before = Marshal.dump(arguments[:replay])
summary = type.from_replay(**arguments, result_policy:type::CURRENT_RESULT_POLICY)
assert(summary['winners'] == %w[alice bob] && !summary['draw'], 'Shared War leaders still become an all-player draw')
assert(summary['places'] == [%w[alice bob], ['carol']], 'War finishing places were lost')
rows = GameRoomTournaments::Standings.calculate(units:%w[alice bob carol],
  results:[summary.slice('participants', 'winners', 'scores', 'score_order', 'places').merge('id'=>'war')],
  points:GameRoomTournaments::Standings::MATCH_POINTS)
assert(rows.to_h { |row| [row['unit'], row['points']] } == {'alice'=>3, 'bob'=>3, 'carol'=>0},
  'Shared-first War match points changed')
assert(Marshal.dump(arguments[:replay]) == before, 'Export changed the finished ordinary War replay')

[%w[Alice Bob], %w[Alice Bob Carol], %w[Alice Bob Carol Dorota],
  %w[Alice Bob Carol Dorota Ewa Filip Grzegorz Hanna]].each do |names|
  args = build.call(names, 0)
  replay = args[:replay]
  counts = replay.state[:piles].transform_values(&:size)
  most = counts.values.max
  leaders = names.select { |name| counts.fetch(name) == most }
  current = type.from_replay(**args, result_policy:type::CURRENT_RESULT_POLICY)
  all_tied = leaders.size == names.size
  assert(current['draw'] == all_tied && current['winners'] == (all_tied ? [] : leaders.map(&:downcase)),
    'The normal unique-winner/full-draw War export changed')
  if current['places']
    assert(current['places'].flatten.sort == names.map(&:downcase).sort &&
      current['places'].first == leaders.map(&:downcase), 'War placement lost a participant')
  end
  assert(current['scores'].nil? && !current.key?('score_order'), 'War placement enabled numeric small points')
end

# Explicit local hook boundary, separate from the complete ordinary histories:
# contested carried cards do not belong to any participant's empty pile.
names = %w[Alice Bob Carol]
state = game.send(:initial_state, names, arguments[:options])
state.update(phase: :finished, draw: true, carried: game.send(:war_deck, arguments[:options]))
empty = GameRoomGames::Replay.new(players:names, winner:nil, draw:true, state:state, accepted_events:[], history:[])
empty_arguments = arguments.merge(replay:empty, events:[], event_count:0)
empty_before = Marshal.dump(state)
empty_summary = type.from_replay(**empty_arguments, result_policy:type::CURRENT_RESULT_POLICY)
assert(empty_summary['draw'] && empty_summary['winners'].empty? && !empty_summary.key?('places') &&
  !empty_summary.key?('resolution'), 'Empty War piles became an administrative all-zero settlement')
assert(Marshal.dump(state) == empty_before, 'Empty-pile export moved carried cards')
assert(game.tournament_small_point_policy(options:arguments[:options]).nil?, 'War small-point policy changed')
puts 'PASS complete accepted War histories: shared first place, card-count places, 2/3/4/8 seats, unchanged v1-v6, replay and no small points'
