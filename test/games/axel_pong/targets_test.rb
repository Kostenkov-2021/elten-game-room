require_relative "../../support/pong_client"

game = GameRoomGames::AxelPong.new
target = game.option_definitions.find { |definition| definition.key == 'target' }
assert(target.choices.map(&:value) == [7, 11, 21, 'custom', 'unlimited'], 'Missing or reordered point targets')
custom = game.option_definitions.find { |definition| definition.key == 'custom_target' }
assert(custom && custom.kind == :integer, 'Custom target is not an edit field')
assert(game.option_definitions.index(custom) == game.option_definitions.index(target) + 1, 'Custom field is not next under Tab')
assert(game.default_options['target'] == 11, 'Default point target changed')
[7, 11, 21, 'unlimited'].each do |value|
  assert(!game.option_visible?(custom, {'target' => value}), 'Custom edit is visible for a different target')
end
assert(game.option_visible?(custom, {'target' => 'custom'}), 'Custom edit stays hidden')
[2, 15, 999].each do |value|
  options = {'target' => 'custom', 'custom_target' => value.to_s}
  assert(game.validation_error(options) == nil, 'A valid custom target was rejected')
  assert(game.points_to_win(options) == value, 'Custom target was not resolved')
end
[nil, '', 'abc', '2.5', 0, 1, -2, 1000].each do |value|
  options = game.normalize_options('target' => 'custom', 'custom_target' => value)
  assert(game.validation_error(options) != nil, "Invalid custom target was silently accepted: #{value.inspect}")
  assert(game.validation_error(options.merge('target' => 'unlimited')) == nil, 'Hidden invalid target blocks unlimited mode')
end
assert(game.points_to_win({}) == 11 && game.points_to_win('target' => 'unlimited') == nil, 'Legacy/unlimited target is incorrect')
assert(game.normalize_options(target: 'custom', custom_target: '15')['custom_target'] == 15, 'Symbol options do not round-trip')

repository = Object.new
def repository.players_for(session); session['__players']; end
def repository.actor_of(event, _session); event['actor']; end
def repository.event_id(event); event['__id']; end
def target_events(sides)
  sides.each_with_index.map do |side, index|
    {'__id' => index + 1, '__insertion_user' => 'Owner', 'action' => 'pong_point', 'value' => "#{index}:#{side}"}
  end
end

[false, true].each do |arcade|
  [%w[A B], %w[A B C D], ['A', 'bot:1:1'], ['A', 'B', 'C', 'bot:1:1']].each do |players|
    options = {'arcade' => arcade, 'team_size' => players.length == 4 ? 2 : 0}
    session = {'__players' => players, '__insertion_user' => 'Owner'}
    [7, 11, 21, 2, 15, 999].each do |limit|
      selected = [7, 11, 21].include?(limit) ? {'target' => limit} : {'target' => 'custom', 'custom_target' => limit}
      session['options'] = JSON.generate(options.merge(selected))
      sides = [0, 1] * (limit - 1) + [0]
      before = game.replay(session, target_events(sides), repository)
      assert(!before.finished?, 'One-point lead ended the match')
      after = game.replay(session, target_events(sides + [0, 1]), repository)
      assert(after.winner == (players.length == 4 ? 'team:0' : 'A'), 'Wrong custom/preset winner')
      assert(after.state[:scores] == [limit + 1, limit - 1], 'Scoring continued after victory')
      assert(after.accepted_events.length == sides.length + 1, 'Wrong final point in replay')
    end
    session['options'] = JSON.generate(options.merge('target' => 'unlimited'))
    events = target_events([0] * 1100 + [1] * 1101)
    replay = game.replay(session, events, repository)
    assert(!replay.finished? && replay.winner == nil, 'Unlimited game acquired a winner')
    assert(replay.state[:scores] == [1100, 1101] && replay.accepted_events.length == events.length, 'Unlimited game stopped counting points')
    assert(replay.history.none? { |entry| entry.text.include?('won the game') }, 'Unlimited game announced a final result')
    replay_again = game.replay(session, events + [events.last], repository)
    assert(replay_again.state[:scores] == replay.state[:scores], 'Duplicate unlimited point scored twice')
    assert(game.replay(session, events.map { |event| event.merge('__insertion_user' => 'Other') }, repository).accepted_events.empty?, 'Unlimited bypasses point authority')
  end
end

[%w[Alice Bob], %w[Alice Bob Carol Dave], ['Alice', 'Bob', 'Carol', 'bot:1:1']].each do |players|
  ['custom', 'unlimited'].each do |mode|
    $spoken_messages.clear
    h = PongHarness.new(players: players, options: {'team_size' => players.length == 4 ? 2 : 0,
      'target' => mode, 'custom_target' => 31})
    begin
      assert(h.network.values.all? { |channel| channel.event_protocol.end_with?('-targets-2') }, 'Old clients could join unsupported point modes')
      h.advance(240)
      if players.none? { |player| GameRoomParticipants.bot?(player) }
        expected = mode == 'custom' ? '31 points to win.' : 'Unlimited match.'
        assert($spoken_messages.any? { |text| text.include?(expected) }, 'Startup announcement has no resolved point target')
      end
      22.times { |index| h.accept_point("#{index}:0") }
      h.advance(400)
      assert(!h.replay.finished? && h.network.values.all?(&:connected?), 'Clients closed a match after the old 21-point limit')
      assert(h.clients.values.none?(&:paused), 'New target left clients paused after a point')
      server = players[h.clients['Alice'].engine.server]
      h.press(server)
      h.advance(8)
      assert(h.clients.values.all? { |client| pong_presented_turn(client) == 1 }, 'Next serve did not reach players and observer')
    ensure
      h.close
    end
  end
end
puts 'PASS Pong targets: custom range, visibility, legacy targets, unlimited replay, singles/doubles, bots, observers and next serve'
