require_relative 'support/new_board_games'

game = GameRoomGames::Checkers.new
repo = NewGamesRepository.new(%w[Alice Bob])
checks = 0
[8, 10, 12].each do |size|
  options = { 'board_size' => size }
  session = { 'options' => JSON.generate(options) }
  replay = game.replay(session, [], repo)
  expected = {}
  (1..size * size / 2).each do |number|
    row, column = (number - 1).divmod(size / 2)
    x = column * 2 + (row.even? ? 1 : 0)
    expected[[x, size - 1 - row]] = number.to_s
  end
  %w[Alice Bob Spectator].each do |viewer|
    spec = game.surface_spec(replay, viewer)
    size.times do |y|
      size.times do |x|
        assert(spec.coordinate_label_sets['numeric'][y][x] == expected.fetch([x,y], ''), "#{size}: numbering #{x},#{y}")
        assert(spec.coordinate_label_sets['algebraic'][y][x] == "#{(65+x).chr}#{y+1}", 'algebraic coordinates changed')
        assert(spec.silent_positions_by_coordinate_label_set['numeric'].include?([x,y]) == !expected.key?([x,y]), 'light square does not match labels')
        checks += 3
      end
    end
  end
  assert(replay.board.flatten.count('0m') == size / 2 * (size / 2 - 1), 'white setup count')
  assert(replay.board.flatten.count('1m') == size / 2 * (size / 2 - 1), 'black setup count')
  if size == 10
    numbered = game.available_board_moves(replay, 'Alice').map { |m| [expected[m.from], expected[m.to]] }
    assert(numbered.select { |a,b| a == '32' }.map(&:last).sort == %w[27 28], '32 destinations')
    assert(numbered.select { |a,b| a == '35' }.map(&:last).sort == %w[30], '35 destinations')
    assert(!numbered.include?(%w[35 25]), '35 to 25 is not a move')
  end
  # Independent ordinary-move geometry on every playable square, both sides.
  expected.keys.each do |origin|
    [0, 1].each do |side|
      board = Array.new(size) { Array.new(size) }
      board[origin[1]][origin[0]] = "#{side}m"
      state = replay.state.merge(board: board, current_player: replay.players[side])
      want = [-1, 1].map { |dx| [origin[0]+dx, origin[1]+(side==0 ? 1 : -1)] }.select { |x,y| x.between?(0,size-1) && y.between?(0,size-1) }
      actual = game.send(:moves_for_state, state, state[:current_player])
      assert(actual.map(&:to).sort == want.sort, "#{size}: adjacent squares #{origin} side #{side}")
      checks += 1
    end
  end
  # Persisted full/incremental replay and the fast bot transition must agree.
  events = []
  36.times do |ply|
    break if replay.finished?
    actor = replay.current_player
    actions = game.legal_actions(replay, actor)
    selection = actions[(ply*7+size) % actions.length]
    before = replay
    fast_status, fast = game.bot_search_transition(before, selection, actor, event_id: events.length+1)
    assert(fast_status == :ok, 'bot transition rejected legal move')
    replay = append_surface_action(game, session, repo, events, replay, actor, selection)
    incremental = game.incremental_replay(before, session, [events.last], repo)
    assert(incremental.state == replay.state, 'incremental geometry diverges from saved events')
    assert(fast.state == replay.state, 'bot transition diverges')
    assert(game.replay(Marshal.load(Marshal.dump(session)), Marshal.load(Marshal.dump(events)), repo).state == replay.state, 'serialized match changed')
    entry = replay.history.find { |h| h.event_id == events.length && h.kind == :move }
    assert(entry.field == expected[[entry.value['to_x'], entry.value['to_y']]], 'history number differs from board')
    checks += 4
  end
end
assert(!game.normalize_options({}).key?('checkers_geometry'), 'Obsolete geometry switch retained')
puts "PASS: #{checks} checkers geometry/replay comparisons (all three sizes)"
