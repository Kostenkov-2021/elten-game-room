require_relative "../../support/pong_client"

[[%w[Alice Bob], [0, 1]], [%w[Alice Bob Carol Dave], [0, 1, 0, 1]],
 [%w[Alice Bob Carol Dave], [1, 0, 0, 1]]].each do |players, teams|
  h = PongHarness.new(players: players, options: players.length == 4 ? {'team_size' => 2, 'team_seats' => teams} : {})
  begin
    h.advance(20)
    watcher = h.clients.fetch('Watcher')
    surface = GameSurfaces.build(h.rules.surface_spec(h.replay, 'Watcher'))
    watcher.attach_view(Form.new(surface.fields), surface)
    snapshot = watcher.snapshot.merge('p' => [3.2, 8.4, 19.6, 26.8].first(players.length))
    watcher.send(:rally_state).public_send(:snapshot=, snapshot)
    commands = %w[perspective_first perspective_second perspective_third perspective_fourth]
    players.each_index do |seat|
      surface.handle_command(commands[seat])
      $spoken_messages.clear
      surface.handle_command('position')
      assert($spoken_messages.last == "#{players[seat]}: #{snapshot['p'][seat].round}.", 'C did not read the observed player and paddle')
      assert(surface.spec.viewer.nil? && !surface.input_active?(Form.new(surface.fields)), 'read-only perspective gave an observer paddle control')
      points = []
      audio = watcher.instance_variable_get(:@audio)
      audio.define_singleton_method(:point) { |scores, **options| points << [scores, options] }
      [0, 1].each do |winning_team|
        before = h.replay.dup
        before.state = h.replay.state.merge(rally: seat * 2 + winning_team)
        after = before.dup
        scores = winning_team == 0 ? [11, 0] : [0, 11]
        after.state = before.state.merge(rally: before.state[:rally] + 1, scores: scores)
        after.winner = players.length == 4 ? "team:#{winning_team}" : players[winning_team]
        watcher.event({'action' => 'pong_point'}, before, after, 'Watcher', h.repository)
        options = points.last.last
        assert(options[:viewer] == teams[seat] && options[:winner] == winning_team && options[:finished], 'final result lost the observed team')
        assert(options[:observer] != true, 'final result still forces a neutral observer announcement')
      end
    end
  ensure
    h.close
  end
end
puts 'PASS observer C and final perspective in Single/Doubles, every seat/team, no control permissions'
