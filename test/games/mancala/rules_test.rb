require_relative "../../support/new_games_fixture"

game = GameRoomGames::Mancala.new
players = %w[Alice Bob]
repository = NewGames116Repository.new(players)

def mancala_session(game, options = {})
  { "options" => JSON.generate(game.normalize_options(options)) }
end

def mancala_state(game, players, options = {})
  game.send(:initial_state, players, game.normalize_options(options))
end

def mancala_replay(game, state)
  GameRoomGames::Replay.new(
    players: state[:players], current_player: state[:current_player],
    winner: state[:winner], draw: state[:tie], state: state,
    accepted_events: [], history: []
  )
end

def mancala_sow(game, state, actor, pit, repository = nil)
  history = []
  event = { "id" => 1, "actor" => actor, "action" => "sow", "value" => pit.to_s }
  applied = game.send(:apply_sow, state, event, actor, repository || NewGames116Repository.new(state[:players]), history)
  [applied, history]
end

assert(game.id == "mancala", "Mancala has the wrong id")
assert(game.minimum_players == 2 && game.maximum_players == 2, "Mancala is not a two player game")
assert(game.supports_bots?, "Mancala does not support bots")
assert(game.perfect_information?, "Mancala hides nothing and must be a perfect information game")
assert(game.default_options["variant"] == "oware", "Oware is not the default game")
assert(game.default_options["stones"] == 4, "four seeds is not the default")
assert(game.default_options["capture"], "capturing is not on by default")
kinds = GameRoomGames::Mancala::VARIANTS
assert(kinds.length == 3, "three games are not offered")
assert(kinds.map(&:value).sort == %w[ayoayo kalah oware], "the games on offer are not the expected ones")
assert(kinds.all? { |choice| choice.label.include?("(") && choice.label.include?(")") },
  "a game is offered without its telling rule in brackets")
assert(kinds.find { |choice| choice.value == "oware" }.label.include?("two or three"),
  "Oware does not say what it captures")
hidden = game.option_definitions.find { |definition| definition.key == "capture" }
assert(!game.option_visible?(hidden, { "variant" => "oware" }), "a Kalah only setting is shown for Oware")
assert(game.option_visible?(hidden, { "variant" => "kalah" }), "the Kalah capture setting is hidden")
assert(game.options_error({ "stones" => 1 }) != nil, "a pit with one stone was accepted")
assert(game.options_error({ "stones" => 9 }) != nil, "a pit with nine stones was accepted")
assert(game.options_error({ "stones" => 4 }) == nil, "the default pit size was refused")

state = mancala_state(game, players)
assert(state[:pits].length == 14, "the board does not hold fourteen pits")
assert(state[:pits].values_at(6, 13) == [0, 0], "the stores do not start empty")
assert(state[:pits].sum == 48, "the board does not hold forty eight stones")
assert(game.send(:facing, 0) == 12 && game.send(:facing, 5) == 7, "the facing pits are wrong")
assert(game.send(:store_index, 0) == 6 && game.send(:store_index, 1) == 13, "the stores are in the wrong place")

kalah = { "variant" => "kalah" }
state = mancala_state(game, players, kalah)
applied, = mancala_sow(game, state, "Alice", 0)
assert(applied, "a legal sowing was refused")
assert(state[:pits][0].zero?, "the sown pit was not emptied")
assert(state[:pits][1, 4] == [5, 5, 5, 5], "the seeds were not dropped one by one")
assert(state[:pits][5] == 4, "one seed too many was dropped")
assert(state[:pits][6].zero?, "a seed reached the store too early")
assert(state[:current_player] == "Bob", "the turn did not pass")

state = mancala_state(game, players, kalah)
applied, history = mancala_sow(game, state, "Alice", 2)
assert(state[:pits][6] == 1, "the last seed did not reach the store")
assert(state[:current_player] == "Alice", "a seed in the store did not give another sowing")
assert(history.any? { |entry| entry.kind == :again }, "sowing again was not announced")

state = mancala_state(game, players, kalah.merge("capture" => false))
state[:pits] = [0, 0, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0, 0]
mancala_sow(game, state, "Alice", 5)
assert(state[:pits][13].zero?, "a seed was dropped into the other store")
assert(state[:pits][6] == 1, "the own store was skipped")
assert(state[:pits][7, 6] == [1, 1, 1, 1, 1, 1], "the seeds did not carry on around the board")
assert(state[:pits][0] == 1, "the sowing did not come back round")

state = mancala_state(game, players, kalah)
state[:pits] = [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0]
applied, history = mancala_sow(game, state, "Alice", 0)
assert(state[:pits][6] == 4, "an empty pit of your own did not capture the facing seeds")
assert(state[:pits][1].zero? && state[:pits][11].zero?, "the captured pits were not emptied")
assert(history.any? { |entry| entry.kind == :capture }, "the capture was not announced")

state = mancala_state(game, players, kalah.merge("capture" => false))
state[:pits] = [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0]
mancala_sow(game, state, "Alice", 0)
assert(state[:pits][1] == 1 && state[:pits][11] == 3, "a table without capturing still captured")

state = mancala_state(game, players, kalah)
state[:pits] = [0, 0, 0, 0, 0, 1, 5, 2, 0, 0, 0, 0, 0, 3]
applied, history = mancala_sow(game, state, "Alice", 5)
assert(state[:phase] == :finished, "the game did not end with an empty side")
assert(state[:pits][13] == 5, "the seeds left on the board did not go to their own store")
assert(state[:pits][7, 6].all?(&:zero?), "the swept pits were not emptied")
assert(state[:winner] == "Alice", "the larger store did not win")
assert(history.any? { |entry| entry.kind == :sweep }, "the sweep was not announced")

state = mancala_state(game, players, kalah)
state[:pits] = [0, 0, 0, 0, 0, 1, 4, 3, 0, 0, 0, 0, 0, 2]
mancala_sow(game, state, "Alice", 5)
assert(state[:phase] == :finished && state[:winner] == nil && state[:tie], "equal stores did not end in a draw")

state = mancala_state(game, players)
mancala_sow(game, state, "Alice", 0)
assert(state[:pits][6].zero? && state[:pits][13].zero?, "Oware sowed into a store")
assert(state[:pits][1, 4] == [5, 5, 5, 5], "Oware did not sow one seed at a time")

state = mancala_state(game, players)
state[:pits] = [13, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
mancala_sow(game, state, "Alice", 0)
assert(state[:pits][0].zero?, "the emptied pit was not passed by while its own seeds were sown")
assert(state[:pits][1] == 2 && state[:pits][2] == 2, "the last two seeds did not carry on past the emptied pit")
assert(state[:pits][3, 3] == [1, 1, 1] && state[:pits][7, 6] == [1, 1, 1, 1, 1, 1], "the lap was not sown evenly")

state = mancala_state(game, players)
state[:pits] = [0, 0, 0, 0, 0, 2, 0, 1, 2, 4, 0, 0, 0, 0]
applied, history = mancala_sow(game, state, "Alice", 5)
assert(state[:pits][6] == 5, "Oware did not capture two and three seeds in a row")
assert(state[:pits][7].zero? && state[:pits][8].zero?, "the captured pits were not emptied")
assert(state[:pits][9] == 4, "a pit that was not two or three was captured")
assert(history.any? { |entry| entry.kind == :capture }, "the Oware capture was not announced")

state = mancala_state(game, players)
state[:pits] = [1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0]
mancala_sow(game, state, "Alice", 5)
assert(state[:pits][7] == 2, "a move taking every seed of the other row changed that row")
assert(state[:pits][6].zero?, "a move taking every seed of the other row still captured")
assert(state[:phase] == :playing, "the game ended although both rows still held seeds")

state = mancala_state(game, players)
state[:pits] = [0, 0, 0, 2, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0]
assert(game.send(:sowable, state, 0) == [5], "Oware did not force a move that feeds the other row")
status, = game.action_for({ "kind" => "grid", "action" => "select", "x" => 3, "y" => 0 },
  mancala_replay(game, state), "Alice")
assert(status == :must_feed, "a move that leaves the other row empty was allowed")

state = mancala_state(game, players)
state[:pits] = [3, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0, 0, 0, 4]
state[:current_player] = "Alice"
assert(game.send(:sowable, state, 0).empty?, "a move was offered although none of them feeds the other row")
game.send(:settle, state, 1, [])
assert(state[:phase] == :finished, "Oware did not end when the other row could not be fed")
assert(state[:pits][6] == 8, "the player who could not feed did not take their own seeds")
assert(state[:winner] == "Alice", "the larger store did not win after the forced ending")

relay = { "variant" => "ayoayo" }
state = mancala_state(game, players, relay)
state[:pits] = [0, 2, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0]
mancala_sow(game, state, "Alice", 1)
assert(state[:pits][3].zero?, "Ayoayo did not pick up the pit it landed in")
assert(state[:pits][4] == 1 && state[:pits][5] == 1, "Ayoayo did not carry the sowing on")
assert(state[:pits][2] == 1, "the first lap was not sown")

state = mancala_state(game, players, relay)
state[:pits] = [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0]
mancala_sow(game, state, "Alice", 0)
assert(state[:pits][6] == 4, "Ayoayo did not capture from an empty pit of your own")
assert(state[:pits][13].zero?, "Ayoayo sowed into a store")

state = mancala_state(game, players)
replay = mancala_replay(game, state)
assert(game.legal_actions(replay, "Alice").length == 6, "every pit is not offered at the start")
assert(game.legal_actions(replay, "Bob").empty?, "the waiting player was offered a move")
assert(game.legal_actions(replay, "Alice").all? { |action| action["y"].zero? }, "a move points at the other row")
status, = game.action_for({ "kind" => "grid", "action" => "select", "x" => 0, "y" => 1 }, replay, "Alice")
assert(status == :other_side, "sowing the other row was accepted")
status, plan = game.action_for({ "kind" => "grid", "action" => "select", "x" => 3, "y" => 0 }, replay, "Alice")
assert(status == :ok && plan.events.first.value == "3", "a legal pit was refused")
state[:pits][0] = 0
status, = game.action_for({ "kind" => "grid", "action" => "select", "x" => 0, "y" => 0 }, mancala_replay(game, state), "Alice")
assert(status == :empty_pit, "an empty pit was sown")

state = mancala_state(game, players)
board = game.surface_spec(mancala_replay(game, state), "Alice")
assert(board.is_a?(GameSurfaces::GridSpec), "the board is not a grid")
assert(board.width == 6 && board.height == 2, "the board is not two rows of six")
assert(board.row_origin == :bottom, "your own row is not the lower one")
assert(board.cells.first.map { |cell| cell[0, 2] } == %w[A1 B1 C1 D1 E1 F1], "your own row is not A1 to F1")
assert(board.cells.last.map { |cell| cell[0, 2] } == %w[A2 B2 C2 D2 E2 F2], "the other row is not A2 to F2")
assert(board.cells.first.first.include?("4 seeds"), "a pit does not say how many seeds it holds")
assert(board.cells.flatten.none? { |cell| cell.include?("Yours") || cell.include?("Theirs") },
  "a pit still carries a spoken side instead of its code")
assert(board.header.include?("Stores"), "the board does not name the stores")

state[:pits][12] = 9
faced = game.surface_spec(mancala_replay(game, state), "Alice")
assert(faced.cells.last.first.include?("9"), "the facing pit is not in the same column")
assert(faced.cells.last.first.start_with?("A2"), "the facing pit lost its code")

shortcuts = game.game_shortcuts(mancala_replay(game, mancala_state(game, players)), "Alice")
keys = shortcuts.map { |shortcut| [shortcut.key, shortcut.modifiers.to_a] }
assert(keys.include?(["t", []]), "T is missing")
assert(keys.include?(["s", []]), "S does not read the stores")
assert(keys.include?(["p", []]), "P does not read your pits")
assert(keys.include?(["p", [:shift]]), "Shift+P does not read the other pits")
assert(keys.none? { |key, _| key == "h" }, "H is reserved for help")
assert(shortcuts.find { |shortcut| shortcut.key == "s" }.message.include?("Alice"), "S does not name the players")

state = mancala_state(game, players)
scored = mancala_replay(game, state)
assert(game.participant_scores(scored).values == [0, 0], "the stores do not start at nothing")
assert(game.bot_position_value(scored, "Alice") == game.bot_position_value(scored, "Bob"),
  "the opening position favours one side")
kalah_scored = mancala_replay(game, mancala_state(game, players, "variant" => "kalah"))
assert(game.bot_action_score(kalah_scored, "Alice", { "x" => 2 }) > game.bot_action_score(kalah_scored, "Alice", { "x" => 0 }),
  "the computer does not prefer a sowing that ends in its store")
assert(game.bot_search_key(scored, "Alice") != game.bot_search_key(scored, "Bob"),
  "both players share one search key")

%w[oware ayoayo kalah].each do |kind|
  kind_session = mancala_session(game, "variant" => kind)
  kind_events = []
  kind_replay = game.replay(kind_session, kind_events, repository)
  rounds = 0
  while !kind_replay.finished?
    rounds += 1
    raise "#{kind} did not finish" if rounds > 600

    mover = kind_replay.current_player
    kind_actions = game.legal_actions(kind_replay, mover)
    raise "no legal actions in #{kind}" if kind_actions.empty?

    kind_choice = game.bot_strategy.choose(actions: kind_actions, actor: mover,
      random_source: NewGames116Random.new, game: game, replay: kind_replay)
    kind_replay = append_action(game, kind_session, repository, kind_events, kind_replay, mover, kind_choice, context_for)
  end
  assert(kind_replay.state[:pits].sum == 48, "#{kind} lost seeds during the game")
  gathered = kind_replay.state[:pits].values_at(6, 13)
  if kind == "oware"
    assert(gathered.any? { |score| score * 2 > 48 } || gathered.sum == 48,
      "Oware ended without anyone holding more than half the seeds")
  else
    assert(gathered.sum == 48, "#{kind} ended with seeds outside the stores")
  end
  assert(kind_replay.winner != nil || kind_replay.draw, "#{kind} has no result")
end

session = mancala_session(game)
events = []
replay = game.replay(session, events, repository)
strategy = game.bot_strategy
random = NewGames116Random.new
context = context_for
guard = 0
while !replay.finished?
  guard += 1
  raise "Mancala did not finish" if guard > 400

  actor = replay.current_player
  actions = game.legal_actions(replay, actor)
  raise "no legal actions" if actions.empty?

  choice = strategy.choose(actions: actions, actor: actor, random_source: random, game: game, replay: replay)
  replay = append_action(game, session, repository, events, replay, actor, choice, context)
end
final = replay.state
assert(final[:pits].sum == 48, "stones were lost during the game")
assert(final[:pits].values_at(6, 13).any? { |score| score * 2 > 48 } || final[:pits].values_at(6, 13).sum == 48,
  "the default game ended without a decided majority")
assert(final[:winner] != nil || replay.draw, "the game has no result")
assert(game.replay(session, events, repository).winner == replay.winner, "the replay is not deterministic")
assert(replay.history.any? { |entry| entry.kind == :sow }, "no sowing reached the history")

skills = GameRoomGames::Mancala::SKILLS
assert(game.default_options["skill"] == "steady", "the middle strength is not the default")
assert(skills.map(&:value) == %w[calm steady sharp], "the three strengths are not the expected ones")
assert(skills.all? { |choice| choice.label.include?("(") }, "a strength is offered without saying what it does")
assert(game.default_options["skill"] != "sharp", "the slowest strength is the default")

sizes = GameRoomGames::Mancala::LEVELS
assert(sizes["calm"][:depth] < sizes["steady"][:depth], "the calm computer does not look less far ahead")
assert(sizes["steady"][:depth] < sizes["sharp"][:depth], "the sharp computer does not look further ahead")
assert(sizes["sharp"][:depth] == 8 && sizes["sharp"][:nodes] == 60_000,
  "the sharp strength is not the search this game used before")
assert(game.strategy_for("calm").equal?(game.strategy_for("calm")), "a strength builds a new search every time")
assert(!game.strategy_for("calm").equal?(game.strategy_for("sharp")), "two strengths share one search")
assert(game.skill(mancala_state(game, players, "skill" => "sharp")) == "sharp", "the table strength is not read")

assert(game.shareable_simulation_snapshot?, "the search may not share a position")
carried = mancala_session(game)
carried_events = []
carried_replay = game.replay(carried, carried_events, repository)
6.times do
  mover = carried_replay.current_player
  break if carried_replay.finished?

  move = game.legal_actions(carried_replay, mover).first
  carried_replay = append_action(game, carried, repository, carried_events, carried_replay, mover, move, context_for)
end
half = carried_events.length / 2
partial = game.replay(carried, carried_events.first(half), repository)
carried_on = game.incremental_replay(partial, carried, carried_events.drop(half), repository)
whole = game.replay(carried, carried_events, repository)
assert(carried_on != nil, "the game cannot carry a position on")
assert(carried_on.state[:pits] == whole.state[:pits], "carrying a position on gives a different board")
assert(carried_on.current_player == whole.current_player, "carrying a position on gives a different turn")
assert(carried_on.accepted_events.length == whole.accepted_events.length, "carrying a position on loses moves")
assert(game.incremental_replay(nil, carried, carried_events, repository) == nil,
  "carrying on from nothing does not fall back to a full replay")

puts "Mancala model tests passed"
