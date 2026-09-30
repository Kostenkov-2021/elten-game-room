require_relative "../../support/new_games_fixture"
require_relative "../../../games/tysiac"

game = GameRoomGames::Tysiac.new
players = %w[Alice Bob Charlie]
repo = NewGames116Repository.new(players)
state = game.send(:initial_state, players, game.default_options)
state.merge!(phase: :playing, current_player: "Alice", taker: "Alice", contract: 100, trick_number: 6, trump: "H",
  hands: {"Alice"=>%w[AC TH],"Bob"=>%w[9H 9S],"Charlie"=>%w[KC JD]}, round_points: {"Alice"=>80,"Bob"=>113,"Charlie"=>0})
replay = GameRoomGames::Replay.new(players: players, state: state, accepted_events: [], history: [])
planner = TysiacPlanning::Planner.new(game, replay, "Alice", GameRoomRandom::SeededSource.new(1))
actions = game.legal_actions(replay, "Alice")
assert(planner.send(:late_contract_control_actions, actions) == actions, "ruffable ace pruned winning trump")
def final_points(game, repo, state)
  return [state[:round_points]["Alice"]] if state[:phase] != :playing
  actor = state[:current_player]
  game.send(:legal_cards, state, actor).flat_map do |card|
    copy = Marshal.load(Marshal.dump(state))
    event = {"id"=>100+copy[:trick_number]*3+copy[:current_trick].length,"actor"=>actor,"action"=>"play","value"=>"normal|#{card}"}
    assert(game.send(:apply_play, copy, event, actor, repo, []), "legal continuation rejected")
    final_points(game, repo, copy)
  end
end
outcomes = actions.to_h do |action|
  copy = Marshal.load(Marshal.dump(state))
  event = {"id"=>90,"actor"=>"Alice","action"=>"play","value"=>action["card"]}
  assert(game.send(:apply_play, copy, event, "Alice", repo, []), "legal opening rejected")
  [action["card"], final_points(game, repo, copy).uniq]
end
assert(outcomes == {"normal|AC"=>[92],"normal|TH"=>[107]}, "counterexample no longer has proven outcomes")
# Supply a fixed legal world to check the actual chooser, not just its filter.
world = planner.send(:world_from_state, hands: Marshal.load(Marshal.dump(state[:hands])))
planner.define_singleton_method(:sampled_worlds) { |_count| [Marshal.load(Marshal.dump(world))] }
assert(planner.choose_play(actions, samples: 1)["card"] == "normal|TH", "planner still misses proven win")

deal = {"action"=>"deal","value"=>"2|1|"+"1"*32}
old = game.send(:deck).map { |card| {"action"=>"play","value"=>"normal|#{card}"} }
state = state.merge(trick_number: 2, trump: nil, hands: {"Alice"=>%w[TC 9C],"Bob"=>%w[AC 9H],"Charlie"=>%w[KC JD]})
make = ->(events) { GameRoomGames::Replay.new(players: players,state: state,accepted_events: events,history: []) }
fresh, prior = make.call([deal]), make.call(old+[deal])
action = {"kind"=>"card","action"=>"select","card"=>"normal|TC"}
assert(game.send(:bot_higher_unseen_count, prior, "Alice", "TC") == 1, "old ace treated as currently played")
assert(game.bot_action_score(fresh,"Alice",action) == game.bot_action_score(prior,"Alice",action), "previous round changed heuristic")
assert(game.bot_observation(fresh,"Alice") == game.bot_observation(prior,"Alice"), "previous round leaked into observation")
current = make.call(old+[deal, {"action"=>"play","value"=>"normal|AC"}])
assert(game.send(:bot_higher_unseen_count,current,"Alice","TC") == 0, "current round plays were lost")
puts "PASS Tysiac: exact counterexample, current-round memory and heuristic; original control regression tested separately"
