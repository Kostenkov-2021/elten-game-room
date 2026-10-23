require_relative '../support/private_card_games'
require_relative '../../games/war'
require_relative '../../lib/tournaments/game_result'

game = GameRoomGames::War.new
war_seen = false
[2, 3, 8].each do |count|
  users = Array.new(count) { |i| "Player#{i}" }
  h, runners = PrivateCardGamesTest.create(game, users: users, options: {'deck'=>'full', 'battle_limit'=>20})
  PrivateCardGamesTest.assert_private(h)
  assert(h.replay(users.first).state[:hands].values.sum(&:size) == 52, 'deal lost cards')
  450.times do |i|
    replay = h.replay(users.first)
    break if replay.finished?
    if i == 10
      h.view(users.first).transfer_ownership(h.view(users.first).participants.find { |participant| participant.user == users.last })
      viewer = users[1]
      expected = h.replay(viewer).state[:hands][viewer].dup
      runners[viewer].close
      h.view(viewer).leave
      h.add_client(viewer)
      assert(h.join(viewer), 'return failed')
      runners[viewer] = runner_for(h, viewer)
      assert(h.replay(viewer).state[:hands][viewer] == expected, 'return reordered pile')
      PrivateCardGamesTest.tick(h, runners)
    end
    actor = replay.current_player
    choice = game.legal_actions(h.replay(actor), actor).first
    assert(choice, 'no top-card action')
    PrivateCardGamesTest.submit(h, runners, actor, choice)
    PrivateCardGamesTest.assert_private(h)
  end
  final = h.replay(users.first)
  assert(final.finished?, "#{count} players did not finish")
  assert(final.accepted_events.size == h.events(users.first).size, 'rejected War event')
  war_seen ||= final.history.any? { |entry| entry.kind == :war }
  assert(final.state[:hands].values.flatten.uniq.size == final.state[:hands].values.sum(&:size), 'duplicated pile card')
  summary = GameRoomTournaments::GameResult.from_replay(game:game, replay:final,
    players:users.map { |user| {'username'=>user, 'account'=>user.downcase} }, options:final.state[:options],
    events:h.events(users.first), event_count:h.events(users.first).size,
    result_policy:GameRoomTournaments::GameResult::CURRENT_RESULT_POLICY)
  counts = final.state[:hands].transform_values(&:size)
  leaders = users.select { |user| counts.fetch(user) == counts.values.max }
  all_tied = leaders.size == users.size
  assert(summary['draw'] == all_tied && summary['winners'] == (all_tied ? [] : leaders.map(&:downcase)),
    'private War exported the wrong final leaders')
  assert(summary['scores'].nil? && !summary.key?('score_order'), 'private War enabled numeric small points')
  runners.each_value(&:close)
end
assert(war_seen, 'war/face-down packet not covered')
puts 'PASS private War: ordered piles, wars, public spoils, 2/3/8 players, host change and cold return'
