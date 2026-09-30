def _(text)
  text
end

require_relative "../../lib/game_simulation"
require_relative "../../games/tic_tac_toe"
require_relative "../../games/four_in_a_row"
require_relative "../../games/farkle"
require_relative "../../games/ninety_nine"

def assert(condition, message)
  raise message if !condition
end

def strategic_choice(environment)
  actor = environment.active_actor
  environment.game.bot_strategy.choose(
    actions: environment.legal_actions(actor),
    observation: environment.observation(actor),
    actor: actor,
    random_source: environment.random_source,
    game: environment.game,
    replay: environment.replay,
    context: environment.context,
    simulation: environment
  )
end

bots = GameRoomParticipants.bots_for(80, 2)

tic = GameRoomGames::TicTacToe.new
tic_environment = GameRoomSimulation::Environment.from_snapshot(
  game: tic,
  session: { "__id" => 1, "table_id" => 80, "options" => "{}" },
  events: [
    { "id" => 1, "actor" => bots[0], "action" => "place", "value" => "1,1" },
    { "id" => 2, "actor" => bots[1], "action" => "place", "value" => "2,1" },
    { "id" => 3, "actor" => bots[0], "action" => "place", "value" => "1,2" },
    { "id" => 4, "actor" => bots[1], "action" => "place", "value" => "2,2" }
  ],
  players: bots,
  seed: 3
)
tic_move = strategic_choice(tic_environment)
assert(tic_move["x"] == 0 && tic_move["y"] == 2, "the exact tic-tac-toe bot missed a forced win")
assert(tic.bot_strategy.last_stats[:completed_depth] >= 5, "tic-tac-toe did not search the remaining game")

four = GameRoomGames::FourInARow.new
winning_four = GameRoomSimulation::Environment.from_snapshot(
  game: four,
  session: { "__id" => 2, "table_id" => 80, "options" => "{}" },
  events: [
    { "id" => 1, "actor" => bots[0], "action" => "drop", "value" => "1" },
    { "id" => 2, "actor" => bots[1], "action" => "drop", "value" => "7" },
    { "id" => 3, "actor" => bots[0], "action" => "drop", "value" => "2" },
    { "id" => 4, "actor" => bots[1], "action" => "drop", "value" => "7" },
    { "id" => 5, "actor" => bots[0], "action" => "drop", "value" => "3" },
    { "id" => 6, "actor" => bots[1], "action" => "drop", "value" => "6" }
  ],
  players: bots,
  seed: 4
)
assert(strategic_choice(winning_four)["x"] == 3, "the Four in a Row bot missed an immediate win")
assert(
  four.bot_strategy.last_stats[:cooperative_yields].to_i > 0,
  "the Four in a Row search did not yield time to ELTEN"
)

blocking_four = GameRoomSimulation::Environment.from_snapshot(
  game: GameRoomGames::FourInARow.new,
  session: { "__id" => 3, "table_id" => 80, "options" => "{}" },
  events: [
    { "id" => 1, "actor" => bots[0], "action" => "drop", "value" => "7" },
    { "id" => 2, "actor" => bots[1], "action" => "drop", "value" => "1" },
    { "id" => 3, "actor" => bots[0], "action" => "drop", "value" => "7" },
    { "id" => 4, "actor" => bots[1], "action" => "drop", "value" => "2" },
    { "id" => 5, "actor" => bots[0], "action" => "drop", "value" => "6" },
    { "id" => 6, "actor" => bots[1], "action" => "drop", "value" => "3" }
  ],
  players: bots,
  seed: 5
)
assert(strategic_choice(blocking_four)["x"] == 3, "the Four in a Row bot did not block an immediate loss")

farkle = GameRoomGames::Farkle.new
catalog = FarklePlanning::OutcomeCatalog.new(farkle)
(1..6).each do |count|
  assert(
    catalog.for_dice(count).sum(&:weight) == 6**count,
    "the Farkle probability catalog lost outcomes for #{count} dice"
  )
end
farkle_state = {
  players: bots,
  options: { "score_limit" => 1_000, "turn_minimum" => 30, "entry_minimum" => 50 },
  scores: { bots[0] => 100, bots[1] => 90 },
  phase: :awaiting_roll,
  current_player: bots[0],
  turn_points: 100,
  dice_to_roll: 1,
  last_roll: [],
  selected_indices: [],
  winner: nil
}
farkle_replay = GameRoomGames::Replay.new(
  players: bots,
  current_player: bots[0],
  winner: nil,
  draw: false,
  state: farkle_state
)
farkle_actions = farkle.legal_actions(farkle_replay, bots[0])
farkle_move = farkle.bot_strategy.choose(
  actions: farkle_actions,
  actor: bots[0],
  random_source: GameRoomRandom::SeededSource.new(7),
  game: farkle,
  replay: farkle_replay
)
assert(farkle_move["action"] == "bank", "the Farkle bot risked a strong turn on one die")

# Regression for the real table state from session 78.  The bot had 270 banked
# points and could safely bank another 225, but a remote chance of reaching the
# score limit used to receive an artificial million-point payoff.  That bonus
# made a two-dice roll look preferable despite a 16/36 Farkle probability.
farkle_regression_state = {
  players: bots,
  options: { "score_limit" => 1_000, "turn_minimum" => 30, "entry_minimum" => 50 },
  scores: { bots[0] => 270, bots[1] => 505 },
  phase: :awaiting_roll,
  current_player: bots[0],
  turn_points: 225,
  dice_to_roll: 2,
  last_roll: [2, 2, 3, 2, 6, 2],
  selected_indices: [],
  winner: nil
}
farkle_regression_replay = GameRoomGames::Replay.new(
  players: bots,
  current_player: bots[0],
  winner: nil,
  draw: false,
  state: farkle_regression_state
)
farkle_regression_move = farkle.bot_strategy.choose(
  actions: farkle.legal_actions(farkle_regression_replay, bots[0]),
  actor: bots[0],
  random_source: GameRoomRandom::SeededSource.new(78),
  game: farkle,
  replay: farkle_regression_replay
)
assert(
  farkle_regression_move["action"] == "bank",
  "the Farkle bot risked 225 points on two dice because of the terminal-score bonus"
)

ninety = GameRoomGames::NinetyNine.new
assert(ninety.default_options["omniscient_bots"] == false, "omniscient Ninety-nine bots are enabled by default")
players = [bots[0], bots[1], GameRoomParticipants.bot_id(80, 3)]
ninety_state = ninety.send(:initial_state, players, ninety.default_options)
ninety_state[:phase] = :playing
ninety_state[:current_player] = players[1]
ninety_state[:direction] = 1
ninety_state[:total] = 25
ninety_state[:hands][players[0]] = ["03C", "09C", "0TC"]
ninety_state[:hands][players[1]] = ["04C", "0AC", "0KC"]
ninety_state[:hands][players[2]] = ["02D", "08D", "0QD"]
ninety_state[:draw_pile] = ["05S", "06S", "07S"]
ninety_state[:discard] = []

preview_action = ninety.send(:card_play_actions, "04C", 25).first
preview = NinetyNinePlanning::Transition.play(ninety, ninety_state, players[1], preview_action)
production = Marshal.load(Marshal.dump(ninety_state))
history = []
repository = GameRoomSimulation::Repository.new(players)
play_event = { "id" => 1, "actor" => players[1], "action" => "play", "value" => "04C|normal" }
draw_event = { "id" => 2, "actor" => players[1], "action" => "draw", "value" => "" }
assert(ninety.send(:apply_play, production, play_event, players[1], repository, history), "production Ninety-nine rejected the preview play")
assert(ninety.send(:apply_draw, production, draw_event, players[1], repository, history), "production Ninety-nine rejected the preview draw")
[:total, :direction, :phase, :current_player, :tokens, :eliminated, :hands, :draw_pile, :discard].each do |field|
  assert(preview[field] == production[field], "Ninety-nine planning drifted from production for #{field}")
end

danger_cases = [
  [30, "03C", "normal", 8],
  [43, "0TC", "minus", 9],
  [33, "09C", "normal", 9],
  [33, "02C", "normal", 8],
  [66, "02C", "normal", 9]
]
danger_cases.each do |old_total, card, mode, expected_opponent_tokens|
  danger_state = ninety.send(:initial_state, players, ninety.default_options)
  danger_state[:phase] = :playing
  danger_state[:current_player] = players[1]
  danger_state[:total] = old_total
  danger_state[:hands][players[1]] = [card]
  danger_state[:draw_pile] = ["05S"]
  action = { "card" => [card, mode].join("|") }
  result = NinetyNinePlanning::Transition.play(ninety, danger_state, players[1], action)
  assert(result != nil, "Ninety-nine planning rejected a danger-threshold case")
  assert(
    result[:tokens][players[0]] == expected_opponent_tokens &&
      result[:tokens][players[2]] == expected_opponent_tokens,
    "Ninety-nine planning applied the wrong exact-33/66 penalty"
  )
end

alternate = Marshal.load(Marshal.dump(ninety_state))
alternate[:hands][players[1]], alternate[:hands][players[2]] = alternate[:hands][players[2]], alternate[:hands][players[1]]
fair_first = NinetyNinePlanning::WorldSampler.new(ninety, ninety_state, players[0]).sample(0)
fair_second = NinetyNinePlanning::WorldSampler.new(ninety, alternate, players[0]).sample(0)
assert(fair_first[:hands] == fair_second[:hands], "the fair Ninety-nine bot peeked at an opponent's real hand")
exact_first = NinetyNinePlanning::WorldSampler.new(ninety, ninety_state, players[0], omniscient: true).sample(0)
exact_second = NinetyNinePlanning::WorldSampler.new(ninety, alternate, players[0], omniscient: true).sample(0)
assert(exact_first[:hands] != exact_second[:hands], "the omniscient Ninety-nine bot ignored known hands")

puts "Strategic bot tests passed"
