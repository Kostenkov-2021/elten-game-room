require_relative '../support/assertions'
require_relative '../support/mahjong_table_game'
require_relative '../../lib/game_random'
include GameRoomTest::Assertions

bot = GameRoomParticipants.bot_id(812, 1)
game = Class.new(GameRoomGames::Base) do
  attr_reader :observations
  def supports_bots?; true; end
  def legal_actions(*, **); [{'kind'=>'command', 'action'=>'test'}]; end
  def bot_observation(*); @observations = @observations.to_i + 1; @observation ||= {'private'=>'same safe object'}; end
end.new
replay = GameRoomGames::Replay.new(board:nil, players:[bot, 'Alice'], current_player:bot,
  winner:nil, draw:false, accepted_events:[], history:[], state:{})
context = GameRoomGames::ActionContext.new(random_source:GameRoomRandom::SeededSource.new(7))
coordinator = GameRoomBots::Coordinator.new
minimal = Class.new do
  def choose(actions:, actor:, random_source:); actions.first; end
end.new
decision = coordinator.decide(game:game, replay:replay, actor:bot, context:context, strategy:minimal)
assert_equal('test', decision.action['action'])
assert_equal(0, game.observations.to_i, 'A strategy which cannot receive observation caused its construction')

[[:explicit, Class.new do
  attr_reader :received
  def choose(actions:, observation:, actor:, random_source:); @received=observation; actions.first; end
end], [:optional, Class.new do
  attr_reader :received
  def choose(actions:, observation:nil); @received=observation; actions.first; end
end], [:external_rest, Class.new do
  attr_reader :received
  def choose(actions:, **extra); @received=extra.fetch(:observation); actions.first; end
end]].each do |label, type|
  strategy = type.new
  before = game.observations.to_i
  result = coordinator.decide(game:game, replay:replay, actor:bot, context:context, strategy:strategy)
  assert_equal(decision.action, result.action, label.to_s)
  assert_equal(before+1, game.observations, "#{label} did not receive exactly one observation")
  assert_equal({'private'=>'same safe object'}, strategy.received)
end

supplied = {'already'=>'built'}
receiver = Class.new do
  attr_reader :received
  def choose(actions:, **extra); @received=extra.fetch(:observation); actions.first; end
end.new
GameRoomBots.choose(receiver, {actions:[decision.action], observation:supplied}) { raise 'Existing observation was rebuilt' }
assert(receiver.received.equal?(supplied), 'Explicit observations must retain the original API/identity')

before = game.observations
game.define_singleton_method(:legal_actions) { |*, **| [] }
assert_equal(nil, coordinator.decide(game:game, replay:replay, actor:bot, context:context, strategy:receiver))
assert_equal(before, game.observations, 'A decision without legal actions built an observation')

# Real Mahjong planning uses the replay, not the generic complete event view.
mahjong = MahjongTableGameTest::Game.new
players = GameRoomParticipants.bots_for(813, 4)
repository = MahjongTableGameTest::Repository.new
session = {'id'=>813, 'players'=>players, 'options'=>JSON.generate('variant'=>'hong_kong', 'seats'=>4)}
random = MahjongTableGameTest::RandomSource.new
ctx = GameRoomGames::ActionContext.new(session_id:813, random_source:random)
initial = mahjong.replay(session, [], repository)
status, plan = mahjong.action_for(mahjong.automatic_action(initial, players.first, context:ctx), initial, players.first, context:ctx)
assert_equal(:ok, status)
event = {'id'=>1, 'actor'=>players.first, 'action'=>plan.events.first.action, 'value'=>plan.events.first.value}
dealt = mahjong.replay(session, [event], repository)
original = Marshal.dump(dealt)
actor = mahjong.active_actors(dealt).first
expected = mahjong.table_bot_selection(dealt, actor)
mahjong.define_singleton_method(:bot_observation) { |*| raise 'Mahjong built an unused full-history view' }
selected = coordinator.decide(game:mahjong, replay:dealt, actor:actor, context:ctx)
assert_equal(expected, selected.action)
assert_equal(original, Marshal.dump(dealt), 'Planning mutated the accepted Mahjong replay')
assert_equal(1, random.calls, 'Selecting a tile consumed new game randomness')
assert_equal(:ok, mahjong.action_for(selected.action, dealt, actor, context:ctx).first)
puts 'PASS lazy observation: precise and legacy keywords, explicit/optional/keyrest observations, original identity, empty actions and genuine Mahjong planning'
