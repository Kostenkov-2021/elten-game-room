require_relative "../../support/new_games_fixture"

def assert(condition, message)
  raise message if !condition
end

def makao_state(game, players, options, current:, hands:, discard:, skip_turns: {})
  state = game.send(:initial_state, players, options)
  state.update(
    phase: :playing,
    current_player: current,
    hands: hands,
    draw_pile: %w[5C 6C 7C 8C 9C TC JC QC AC 5D 6D 7D],
    discard: [discard],
    declared_suit: discard[1],
    declared_rank: discard[0],
    skip_turns: players.to_h { |player| [player, skip_turns.fetch(player, 0)] }
  )
  state
end

def play_card(game, state, repository, actor, card, choice: "", id: 1)
  history = []
  event = { "id" => id, "actor" => actor, "action" => "play", "value" => "#{card}|#{choice}" }
  assert(game.send(:apply_play, state, event, actor, repository, history), "Makao rejected #{card} played by #{actor}")
  history
end

game = GameRoomGames::Makao.new

# A waiting player remains the recipient of a two/three attack. The waiting
# status prevents a defence, so accepting the cards also consumes one of the
# queued waiting turns; the attack must never rebound to its author.
players = %w[Alice Bob]
repository = NewGames116Repository.new(players)
options = game.normalize_options("profile" => "simple")
state = makao_state(
  game, players, options,
  current: "Alice",
  hands: { "Alice" => %w[2C 9S], "Bob" => %w[3D 5H] },
  discard: "7C",
  skip_turns: { "Bob" => 2 }
)
play_card(game, state, repository, "Alice", "2C")
assert(state[:current_player] == "Bob", "a two rebounded from the waiting player to its author")
assert(state[:draw_penalty] == 2, "a two did not create its normal draw penalty")

replay = GameRoomGames::Replay.new(players: players, current_player: "Bob", state: state)
actions = game.legal_actions(replay, "Bob")
assert(actions.any? { |action| action["action"] == "draw" }, "the waiting target cannot accept the draw penalty")
assert(actions.none? { |action| action["action"] == "play" }, "the waiting target was allowed to defend with a three")
assert(
  game.automatic_action(replay, "Bob") == { "kind" => "command", "action" => "draw" },
  "the waiting target did not accept the draw penalty automatically"
)

before = state[:hands]["Bob"].length
draw = { "id" => 2, "actor" => "Bob", "action" => "draw", "value" => "" }
assert(game.send(:apply_draw, state, draw, "Bob", repository, []), "the waiting target could not draw the penalty")
assert(state[:hands]["Bob"].length == before + 2, "the waiting target drew the wrong number of cards")
assert(state[:skip_turns]["Bob"] == 1, "accepting the cards did not consume exactly one waiting turn")
assert(state[:current_player] == "Alice", "the two-player game did not return to the attacker after the waiting turn")

# Without a waiting penalty, the existing defence rules remain unchanged.
defence = makao_state(
  game, players, options,
  current: "Alice",
  hands: { "Alice" => %w[2C 9S], "Bob" => %w[3D 5H] },
  discard: "7C"
)
play_card(game, defence, repository, "Alice", "2C")
defence_replay = GameRoomGames::Replay.new(players: players, current_player: "Bob", state: defence)
assert(
  game.legal_actions(defence_replay, "Bob").any? { |action| action["action"] == "play" && JSON.parse(action["cards"]).include?("3D") },
  "the fix removed the normal mixed two/three defence"
)
assert(game.automatic_action(defence_replay, "Bob") == nil, "a player able to defend was forced to draw")

# With more players, the physical next seat pays the penalty and play then
# continues to the following seat.
players = %w[Alice Bob Carol]
repository = NewGames116Repository.new(players)
state = makao_state(
  game, players, options,
  current: "Alice",
  hands: { "Alice" => %w[3C 9S], "Bob" => %w[2D 5H], "Carol" => %w[6H 8H] },
  discard: "7C",
  skip_turns: { "Bob" => 1 }
)
play_card(game, state, repository, "Alice", "3C")
assert(state[:current_player] == "Bob" && state[:draw_penalty] == 3, "a three skipped its waiting recipient")
assert(game.send(:apply_draw, state, { "id" => 2, "actor" => "Bob" }, "Bob", repository, []), "Bob could not accept three cards")
assert(state[:skip_turns]["Bob"] == 0 && state[:current_player] == "Carol", "multiplayer turn order changed after the penalty")

# Attacking kings and jokers represented as draw cards use the same recipient
# rule instead of retaining a separate buggy path.
options = game.normalize_options("profile" => "joker")
king = makao_state(
  game, players, options,
  current: "Alice",
  hands: { "Alice" => %w[KS 9C], "Bob" => %w[KH 5H], "Carol" => %w[6H 8H] },
  discard: "7S",
  skip_turns: { "Bob" => 1 }
)
play_card(game, king, repository, "Alice", "KS")
assert(king[:current_player] == "Bob" && king[:draw_penalty] == 5, "an attacking king skipped its waiting recipient")
king_replay = GameRoomGames::Replay.new(players: players, current_player: "Bob", state: king)
assert(game.legal_actions(king_replay, "Bob").none? { |action| action["action"] == "play" },
  "a waiting player defended an attacking king")

joker = makao_state(
  game, players, options,
  current: "Alice",
  hands: { "Alice" => %w[X0 9C], "Bob" => %w[3D 5H], "Carol" => %w[6H 8H] },
  discard: "7C",
  skip_turns: { "Bob" => 1 }
)
play_card(game, joker, repository, "Alice", "X0", choice: "2C")
assert(joker[:current_player] == "Bob" && joker[:draw_penalty] == 2,
  "a joker represented as a two skipped its waiting recipient")

puts "Makao waiting-player penalty target tests passed"
