def _(text); text; end
require_relative "../../../lib/game_simulation"
require_relative "../../../games/tic_tac_toe"

LINES = [[0,1,2],[3,4,5],[6,7,8],[0,3,6],[1,4,7],[2,5,8],[0,4,8],[2,4,6]].freeze
def oracle(board, moving, memo)
  return -1 if LINES.any? { |line| line.all? { |i| board[i] == 1 - moving } }
  return 0 if board.none?(nil)
  key = [board, moving]
  return memo[key] if memo.key?(key)
  memo[key] = board.each_index.filter_map do |index|
    next unless board[index] == nil
    child = board.dup; child[index] = moving
    -oracle(child, 1 - moving, memo)
  end.max
end

game = GameRoomGames::TicTacToe.new
stack = [GameRoomSimulation::Environment.new_game(game:game, players:%w[A B], seed:212)]
seen = {}; memo = {}; checked = 0
until stack.empty?
  environment = stack.pop
  r = environment.replay
  key = [r.board, r.current_player].inspect
  next if seen[key]
  seen[key] = true
  next if r.finished?
  actor = environment.active_actor
  moving = r.players.index(actor)
  actions = environment.legal_actions(actor)
  chosen = game.bot_strategy.choose(actions:actions, actor:actor, random_source:environment.random_source,
    game:game, replay:r, context:environment.context, simulation:environment)
  board = r.board.flatten
  after = board.dup
  after[chosen['y'] * 3 + chosen['x']] = moving
  actual = -oracle(after, 1 - moving, memo)
  expected = oracle(board, moving, memo)
  raise "suboptimal choice #{key}: #{chosen.inspect}" unless actual == expected
  checked += 1
  actions.each do |action|
    child = environment.fork_for_search
    raise 'rejected legal move' unless child.step_for_search(action, actor:actor) == :ok
    stack << child
  end
end
raise "unexpected coverage #{seen.length}/#{checked}" unless seen.length == 5478 && checked == 4520
puts "Tic-tac-toe: all #{checked} playable positions optimal; #{seen.length} reachable positions checked."
