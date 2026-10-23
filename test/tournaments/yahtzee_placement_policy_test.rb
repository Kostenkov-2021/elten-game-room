require_relative '../support/cat_head_tail'
require_relative '../../games/yahtzee'
require_relative '../../lib/tournaments/game_result'
require_relative '../../lib/tournaments/standings'

game = GameRoomGames::Yahtzee.new
result_type = GameRoomTournaments::GameResult
options = game.default_options.merge('extra_categories'=>false, 'upper_bonus'=>false,
  'yahtzee_bonus'=>false, 'joker_rule'=>false)
session = {'options'=>JSON.generate(options)}
build = lambda do |dice_by_player, eliminated: nil|
  names = dice_by_player.keys
  repository = CatHeadTailRepository.new(names)
  events = []
  GameRoomGames::Yahtzee::STANDARD_CATEGORIES.each do |category|
    dice_by_player.each do |name, dice|
      if name == eliminated && category == GameRoomGames::Yahtzee::STANDARD_CATEGORIES.last
        # This is the model's trusted projection dialect, not a claim that
        # an ordinary client's game_action can authorize an elimination.
        events << cht_event(events.length + 1, name, 'tournament_elimination', JSON.generate([names.index(name)])).
          merge('__tournament_elimination'=>true)
        next
      end
      events << cht_event(events.length + 1, name, 'roll', dice)
      events << cht_event(events.length + 1, name, 'score', category)
    end
  end
  replay = game.replay(session, events, repository)
  assert(replay.finished? && replay.accepted_events == events, 'The complete scoring history must actually finish')
  roster = names.map { |name| {'username'=>name, 'account'=>name.downcase} }
  {game:game, replay:replay, players:roster, options:options, event_count:events.size, events:events}
end

arguments = build.call({'Ala'=>'6,6,6,6,6', 'Bartek'=>'6,6,6,6,6', 'Celina'=>'1,2,3,4,6'})
assert(game.participant_scores(arguments[:replay]).values == [170, 170, 62], 'Original accepted subset-tie fixture changed')
expected_legacy = {'participants'=>%w[ala bartek celina], 'winners'=>[], 'draw'=>true,
  'scores'=>nil, 'event_count'=>78}
# Explicit persisted policy strings, not CURRENT: previously accepted v1-v6
# results must retain their exact summaries after a new policy is introduced.
%w[game-owned-scores-v1 game-owned-result-v2 game-owned-result-v3
  game-owned-result-v4 game-owned-result-v5 game-owned-result-v6].each do |policy|
  expected = expected_legacy.dup
  expected['score_order'] = 'higher' if %w[game-owned-result-v4 game-owned-result-v5].include?(policy)
  summary = result_type.from_replay(**arguments, result_policy:policy)
  assert(summary == expected, "Historical Yahtzee summary changed for #{policy}")
end
before = Marshal.dump(arguments[:replay].state)
summary = result_type.from_replay(**arguments, result_policy:result_type::CURRENT_RESULT_POLICY)
assert(summary['winners'] == %w[ala bartek] && !summary['draw'], 'Subset leaders still become an all-player draw')
assert(summary['places'] == [%w[ala bartek], ['celina']], 'Shared first place was lost')
rows = GameRoomTournaments::Standings.calculate(units:%w[ala bartek celina],
  results:[summary.slice('participants', 'winners', 'scores', 'score_order', 'places').merge('id'=>'subset')],
  points:GameRoomTournaments::Standings::MATCH_POINTS)
assert(rows.to_h { |row| [row['unit'], row['points']] } == {'ala'=>3, 'bartek'=>3, 'celina'=>0}, 'Subset tie points changed')
assert(Marshal.dump(arguments[:replay].state) == before, 'Export mutated the finished game')

[
  [{'Ala'=>'6,6,6,6,6', 'Bartek'=>'6,6,6,6,6', 'Celina'=>'6,6,6,6,6'}, true, nil],
  [{'Ala'=>'6,6,6,6,6', 'Bartek'=>'5,5,5,5,5', 'Celina'=>'1,2,3,4,6', 'Dorota'=>'1,2,3,4,6'},
    false, [['ala'], ['bartek'], %w[celina dorota]]]
].each do |dice, draw, places|
  args = build.call(dice)
  current = result_type.from_replay(**args, result_policy:result_type::CURRENT_RESULT_POLICY)
  assert(current['draw'] == draw && current['places'] == places, 'Full tie or lower shared places changed')
  assert(current['scores'].nil? && !current.key?('score_order'), 'Yahtzee finishing places leaked numeric small points')
end
assert(summary['scores'].nil? && !summary.key?('score_order') && game.tournament_small_point_policy(options:options).nil?,
  'Subset-tie repair enabled small points')

eliminated = build.call({'Ala'=>'6,6,6,6,6', 'Bartek'=>'6,6,6,6,6', 'Celina'=>'1,2,3,4,6', 'Dorota'=>'6,6,6,6,6'},
  eliminated:'Dorota')
assert(game.participant_scores(eliminated[:replay])['Dorota'] > game.participant_scores(eliminated[:replay])['Celina'],
  'The eliminated player must have a higher partial score than the surviving third-place player')
finished = result_type.from_replay(**eliminated, result_policy:result_type::CURRENT_RESULT_POLICY)
groups = result_type.eliminations(eliminated[:replay], players:eliminated[:players])
final = result_type.with_eliminations(finished, groups)
assert(final['places'] == [%w[ala bartek], ['celina'], ['dorota']] && final['winners'] == %w[ala bartek],
  'Elimination restored a departed winner or promoted their partial points')
puts 'PASS complete accepted Yahtzee matches: shared first/lower places, full draw, eliminated partial scores, no small points and exact persisted v1-v6 summaries'
