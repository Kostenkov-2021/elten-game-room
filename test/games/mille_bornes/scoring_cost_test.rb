require_relative '../../support/elten_array_shuffle'
require_relative '../../support/mille_bornes'
include MilleBornesTest

[[2, 0], [8, 0], [8, 4]].each do |count, teams|
  players = Array.new(count) { |index| "Player#{index + 1}" }
  fixture = Fixture.new(players: players, options: { 'team_count' => teams })
  current = fixture.start
  actor = current.current_player
  current = fixture.act(actor, fixture.game.legal_actions(current, actor).find { |action| action['action'] == 'draw' },
    before: current)
  game = fixture.game
  before = Marshal.dump(current)
  observation = game.method(:bot_observation)
  copies = 0
  game.define_singleton_method(:bot_observation) do |replay, viewer|
    copies += 1
    observation.call(replay, viewer)
  end

  actions = game.legal_actions(current, actor)
  assert(actions.length > 1, 'Scoring fixture needs several real candidates')
  scores = actions.map { |action| game.bot_action_score(current, actor, action) }
  equal(0, copies, 'Internal candidate scoring must not deep-copy an entire observation')
  decision = GameRoomBots::Coordinator.new.decide(game: game, replay: current, actor: actor,
    context: fixture.context, controlled_actors: [actor])
  equal(1, copies, 'Coordinator retains the single isolated public observation')
  assert(actions.include?(decision.action), 'Coordinator did not return a legal candidate')
  equal(scores.max, game.bot_action_score(current, actor, decision.action), 'Choice no longer maximizes the same heuristic')
  equal(before, Marshal.dump(current), 'Scoring or choosing modified the live replay')

  public_copy = game.bot_observation(current, actor)
  public_copy.fetch('tracks').first[:miles] = 777
  public_copy.fetch('hand').clear
  equal(before, Marshal.dump(current), 'Public observation lost its defensive copy')
end

puts 'PASS Mille Bornes scoring copy budget: 2/8 players, teams, legal choice, immutable replay and isolated public observation'
