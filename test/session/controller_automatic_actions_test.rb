require_relative "../support/new_games_fixture"

players = %w[Alice Bob Carol]
context = GameRoomGames::ActionContext.new(now: 1000, table_owner: 'Bob')
failures = []

game = GameRoomGames::Makao.new
state = game.send(:initial_state, players, game.default_options)
state.update(phase: :playing, current_player: 'Bob', draw_penalty: 2,
  hands: {'Alice'=>%w[9S], 'Bob'=>%w[5H], 'Carol'=>%w[6H]},
  draw_pile: %w[5C 6C 7C], discard: ['2C'], declared_suit: 'C', declared_rank: '2')
makao = GameRoomGames::Replay.new(players: players, current_player: 'Bob', state: state)

monopoly_game = GameRoomGames::Monopoly.new
estate = monopoly_game.send(:initial_state, players, monopoly_game.default_options)
estate.update(phase: :property_decision, current_player: 'Bob')
estate[:positions]['Bob'] = 1
estate[:cash]['Bob'] = 0
monopoly = GameRoomGames::Replay.new(players: players, current_player: 'Bob', state: estate)

[[game, makao, 'draw'], [monopoly_game, monopoly, 'decline']].each do |definition, replay, expected|
  ['Alice', 'Bob', 'Carol'].each do |owner|
    actor = definition.automatic_actor(replay, 'Bob', table_owner: owner)
    selected = definition.automatic_action(replay, actor, context: context)
    unless actor == 'Bob' && selected && selected['action'] == expected
      failures << "#{definition.id}: master #{owner}, actor #{actor}, expected Bob's #{expected}, got #{selected.inspect}"
      next
    end
    status, = definition.action_for(selected, replay, actor, context: context)
    assert(status == :ok, "#{definition.id}: automatic action was not legal")
  end
end

# Table-wide actions still belong to the original first seat in the replay;
# the current master performs them through the authenticated controller path.
uno = GameRoomGames::Uno.new
initial = GameRoomGames::Replay.new(players: players, state: uno.send(:initial_state, players, uno.default_options))
actor = uno.automatic_actor(initial, 'Bob', table_owner: 'Bob')
assert(actor == 'Alice' && uno.automatic_action(initial, actor)['action'] == 'deal', 'New master lost the shared automatic deal')
raise failures.join("\n") unless failures.empty?
puts 'Handover automatic actors: own Makao penalty and Monopoly purchase, shared UNO deal: OK'
