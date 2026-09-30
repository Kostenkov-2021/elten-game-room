require_relative "../../tools/training/match_runner"
def _(text)
  text
end

def n_(singular, plural, count)
  count.to_i == 1 ? singular : plural
end

require_relative "../../lib/game_simulation"
require_relative "../../content/monopoly_boards"
require_relative "../../games/monopoly"
require_relative "../../games/yahtzee"
require_relative "../../games/uno"
require_relative "../../games/poker"
require_relative "../../games/makao"

def assert(condition, message)
  raise message if !condition
end

bots = GameRoomParticipants.bots_for(1, 3)

[
  [GameRoomGames::Yahtzee.new, {}, 2_000],
  [GameRoomGames::Makao.new, { "profile" => "simple" }, 5_000],
  [GameRoomGames::Poker.new, { "starting_chips" => 100, "small_blind" => 5, "big_blind" => 10 }, 5_000],
  [GameRoomGames::Poker.new, {
    "variant" => "draw", "starting_chips" => 100, "ante" => 5,
    "betting" => "pot_limit", "raise_cap_enabled" => true,
    "raise_cap" => 3, "jacks_or_better" => true
  }, 8_000]
].each_with_index do |(game, options, limit), index|
  result = GameRoomSimulation::MatchRunner.new(
    game: game,
    players: bots,
    options: options,
    max_actions: limit
  ).run(seed: 1160 + index)
  label = "#{game.name} #{options.inspect}"
  assert(result.finished?, "#{label} did not finish: #{result.reason} after #{result.actions} actions")
  assert(result.events.length >= result.actions, "#{label} lost accepted actions")
end

joker_makao = GameRoomSimulation::Environment.new_game(
  game: GameRoomGames::Makao.new,
  players: bots,
  options: { "profile" => "joker" },
  seed: 1168
)
400.times do
  break if joker_makao.finished?

  actor = joker_makao.active_actor
  actions = joker_makao.legal_actions(actor)
  assert(actor != nil && !actions.empty?, "Joker Makao reached a live state without an action")
  selected = joker_makao.game.bot_strategy.choose(
    actions: actions,
    observation: joker_makao.observation(actor),
    actor: actor,
    random_source: joker_makao.random_source,
    game: joker_makao.game,
    replay: joker_makao.replay,
    context: joker_makao.context,
    simulation: joker_makao
  )
  assert(joker_makao.step(selected, actor: actor) == :ok,
    "Joker Makao bot produced an invalid action")
end
assert(joker_makao.replay.accepted_events.length >= 100 || joker_makao.finished?,
  "Joker Makao stopped making progress")

# UNO rounds can intentionally continue for a long time when accumulated draw
# penalties keep returning through a recycled deck. Exercise every agreed deck
# and interactive variant for a substantial bounded game instead of mistaking a
# long but progressing round for a deadlock.
[
  { "score_limit" => 80 },
  {
    "deck" => "no_mercy", "score_limit" => 250, "advanced_responses" => true,
    "interceptions" => true, "super_interceptions" => true, "zero_seven" => true
  },
  { "deck" => "flip", "score_limit" => 80 },
  { "score_limit" => 80, "buzzers" => true }
].each_with_index do |options, variant_index|
  environment = GameRoomSimulation::Environment.new_game(
    game: GameRoomGames::Uno.new,
    players: bots,
    options: options,
    seed: 1170 + variant_index
  )
  accepted_before = environment.replay.accepted_events.length
  400.times do
    break if environment.finished?

    actor = environment.active_actor
    actions = environment.legal_actions(actor)
    assert(actor != nil && !actions.empty?, "UNO #{options.inspect} reached a live state without an action")
    selected = environment.game.bot_strategy.choose(
      actions: actions,
      observation: environment.observation(actor),
      actor: actor,
      random_source: environment.random_source,
      game: environment.game,
      replay: environment.replay,
      context: environment.context,
      simulation: environment
    )
    assert(environment.step(selected, actor: actor) == :ok,
      "UNO #{options.inspect} bot produced an invalid action")
  end
  assert(environment.replay.accepted_events.length >= accepted_before + 100 || environment.finished?,
    "UNO #{options.inspect} stopped making progress")
end

# Monopoly can intentionally be a long game. Exercise many complete turns and
# require every generated bot action to remain valid while cash, ownership and
# auctions change repeatedly.
environment = GameRoomSimulation::Environment.new_game(
  game: GameRoomGames::Monopoly.new,
  players: bots,
  options: { "auction_unsold" => true, "free_parking_jackpot" => true },
  seed: 1169
)
500.times do
  break if environment.finished?

  actor = environment.active_actor
  actions = environment.legal_actions(actor)
  assert(actor != nil && !actions.empty?, "Monopoly reached a live state without an action")
  selected = environment.game.bot_strategy.choose(
    actions: actions,
    observation: environment.observation(actor),
    actor: actor,
    random_source: environment.random_source,
    game: environment.game,
    replay: environment.replay,
    context: environment.context,
    simulation: environment
  )
  assert(environment.step(selected, actor: actor) == :ok, "Monopoly bot produced an invalid action")
end
assert(environment.replay.accepted_events.length >= 100 || environment.finished?,
  "Monopoly did not sustain a substantial match")

puts "New games complete-match tests passed"
