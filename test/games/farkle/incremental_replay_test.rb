require_relative '../../support/farkle'
require_relative '../../../lib/game_simulation'

game = GameRoomGames::Farkle.new
comparisons = 0
[1, 2].each do |version|
  [9, 137, 1979].each do |seed|
    # Build fixtures using only full replay, independently of the new reducer.
    source = GameRoomGames::Farkle.new
    def source.incremental_replay(*); nil; end
    env = GameRoomSimulation::Environment.new_game(game: source, players: %w[Alice Bob Carol], seed: seed,
      options: {'score_limit' => 300, 'entry_minimum' => 0, 'turn_minimum' => 0, 'farkle_rules_version' => version})
    150.times do
      break if env.finished?
      if env.replay.state[:phase] == :selecting
        2.times { assert(env.step({'kind' => 'command', 'action' => 'toggle', 'index' => 0}) == :ok, 'Fixture toggle failed') }
      end
      action = env.legal_actions.find { |choice| choice['action'] == 'bank' } || env.legal_actions.first
      assert(env.step(action) == :ok, 'Fixture action failed')
    end
    assert(env.finished?, "Fixture did not finish: #{version}/#{seed}")
    received = env.events.flat_map do |event|
      [event.merge('actor' => 'Outsider'), event.merge('action' => 'invalid'), event]
    end
    received << farkle_event(100_000, 'Alice', 'roll', '1,1,1,1,1,1')
    [1, 7, received.length].each do |batch_size|
      before = game.replay(env.session, [], env.repository)
      prefix = []
      received.each_slice(batch_size) do |batch|
        untouched = Marshal.dump(before)
        prefix.concat(batch)
        actual = game.incremental_replay(before, env.session, batch, env.repository)
        expected = game.replay(env.session, prefix, env.repository)
        assert(actual, 'Missing incremental Farkle replay')
        assert(actual == expected, "Incremental state/history changed: #{version}/#{seed}/#{prefix.length}")
        before.players.each do |actor|
          assert(game.legal_actions(actual, actor) == game.legal_actions(expected, actor), 'Incremental legal actions changed')
        end
        assert(Marshal.dump(before) == untouched, 'Incremental reducer mutated its input')
        before = actual
        comparisons += 1
      end
      child = game.incremental_replay(before, env.session, [], env.repository)
      untouched = Marshal.dump(before)
      child.state[:scores]['Alice'] += 10
      child.state[:last_roll] << 6
      child.state[:selected_indices] << 0
      child.history.clear
      child.accepted_events.clear
      assert(Marshal.dump(before) == untouched, 'Incremental result shares writable state/containers with its parent')
    end
    changed_options = env.session.merge('options' => JSON.generate(source.default_options))
    assert(game.incremental_replay(env.replay, changed_options, [], env.repository) == nil, 'Changed rules reused an old model')
    changed_players = GameRoomSimulation::Repository.new(%w[Carol Bob Alice])
    assert(game.incremental_replay(env.replay, env.session, [], changed_players) == nil, 'Changed seats reused an old model')
    replacement = env.session.merge('__initial_players' => env.replay.players,
      '__seat_changes' => [{'id' => 10, 'players' => %w[Dave Bob Carol]}])
    assert(game.incremental_replay(env.replay, replacement, [], env.repository) == nil, 'Historical seat projection bypassed full replay')
  end
end
assert(game.incremental_replay(nil, {}, [], nil) == nil, 'Missing model did not use full replay fallback')
puts "PASS Farkle incremental replay: #{comparisons} complete states, history/action order, rejected events, both rules versions, endings and isolation"
