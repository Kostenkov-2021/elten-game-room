def _(text); text; end
def n_(singular, plural, count); count.to_i == 1 ? singular : plural; end
require_relative "../../lib/game_simulation"
require_relative "../../games/monopoly"
require_relative "../../games/poker"

summaries = []
[
  [GameRoomGames::Monopoly.new, {}, 280],
  [GameRoomGames::Poker.new, { "starting_chips" => 1000 }, 140],
  [GameRoomGames::Poker.new, { "variant" => "draw", "starting_chips" => 1000 }, 140]
].each_with_index do |(game, options, limit), index|
  environment = GameRoomSimulation::Environment.new_game(game: game,
    players: GameRoomParticipants.bots_for(1, 3), options: options, seed: 2080 + index)
  counts = Hash.new(0)
  proposals = {}
  limit.times do
    break if environment.finished?
    actor = environment.active_actor
    state = environment.replay.state
    actions = environment.legal_actions(actor)
    raise "#{game.id}: no action" if actions.empty?
    selected = game.bot_strategy.choose(actions: actions, actor: actor, random_source: environment.random_source,
      game: game, replay: environment.replay, context: environment.context)
    counts[selected["action"]] += 1
    if game.id == "monopoly" && selected["action"] == "trade_offer"
      key = [actor, state[:turn_number]]
      raise "Repeated bot proposal in one turn" if proposals[key]
      proposals[key] = true
    end
    raise "#{game.id}: rejected bot action #{selected.inspect}" if environment.step(selected, actor: actor) != :ok
    replay = game.replay(environment.session, environment.events, environment.repository)
    raise "#{game.id}: replay diverged" unless replay.state == environment.replay.state
  end
  summaries << { game: game.id, variant: options["variant"], moves: counts, finished: environment.finished? }
end
puts JSON.pretty_generate(summaries)
