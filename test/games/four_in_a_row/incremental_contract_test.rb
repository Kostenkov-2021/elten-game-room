require_relative "../../support/cat_head_tail"
require_relative "../../../games/four_in_a_row"

game = GameRoomGames::FourInARow.new
repository = CatHeadTailRepository.new(%w[Alice Bob])
session = {}
traces = [[1, 7, 2, 7, 3, 6, 4], [1, 2, 1, 2, 1, 2, 1], [1, 1, 1, 1, 1, 1, 1, 2]]
traces << [2,4,2,5,4,4,7,7,2,5,5,4,3,4,5,3,5,3,1,2,4,6,2,1,7,2,1,1,7,6,6,5,7,7,3,6,1,6,3,3,1,6]
random = Random.new(84)
# Choose nonwinning moves when possible to cover complete draw positions as
# well as terminal wins; this is deterministic model input, not a bot change.
20.times do
  events = []
  loop do
    replay = game.replay(session, events, repository)
    break if replay.finished?
    candidates = game.legal_actions(replay, replay.current_player).map { |action| action.fetch('x') + 1 }
    quiet = candidates.select do |column|
      event = cht_event(events.length + 1, replay.current_player, 'drop', column)
      game.replay(session, events + [event], repository).winner.nil?
    end
    choices = quiet.empty? ? candidates : quiet
    events << cht_event(events.length + 1, replay.current_player, 'drop', choices.fetch(random.rand(choices.length)))
  end
  traces << events.map { |event| event.fetch('value').to_i }
end
draws = 0
traces.each do |columns|
  events = []
  position = game.replay(session, events, repository)
  columns.each do |column|
    actor = position.current_player
    additions = [cht_event(events.length + 1, 'Watcher', 'drop', '3'),
      cht_event(events.length + 2, actor, 'unknown', '3'),
      cht_event(events.length + 3, actor, 'drop', column)]
    unchanged = Marshal.dump(position)
    child = game.incremental_replay(position, session, additions, repository)
    events.concat(additions)
    assert(child.to_h == game.replay(session, events, repository).to_h, 'incremental/full state or history divergence')
    assert(Marshal.dump(position) == unchanged, 'incremental application mutated parent branch')
    assert(child.state.nil?, 'board replay gained a synthetic state Hash')
    position = child
  end
  draws += 1 if position.draw
  if position.finished?
    late = cht_event(events.length + 1, position.current_player, 'drop', 2)
    assert(game.incremental_replay(position, session, [late], repository).to_h == position.to_h, 'terminal incremental position accepted late event')
  end
end
assert(draws.positive?, 'deterministic traces did not cover a complete draw')
empty = game.replay(session, [], repository)
left = game.incremental_replay(empty, session, [cht_event(1, 'Alice', 'drop', 1)], repository)
right = game.incremental_replay(empty, session, [cht_event(1, 'Alice', 'drop', 7)], repository)
assert(left.board[0][0] == 0 && right.board[0][0].nil? && empty.board.flatten.compact.empty?, 'sibling boards share mutable cells')
assert(game.incremental_replay(nil, session, [], repository).nil?, 'missing parent lost fallback')
puts "FourInARow: #{traces.length} full/incremental traces, #{draws} draws, invalid/late actions and branch isolation OK"
