require_relative "../../games/catalog"
require_relative "../../lib/game_reduction"
require_relative "../../lib/game_snapshot"
require_relative "../support/assertions"
require_relative "../support/contract_values"
include GameRoomTest::Assertions

[
  [GameRoomGames::Categories.new, %w[category_round answer_commit answers_closed answer_nonce answer_0 review_started review_correct review_clear review_finished review_commit round_score round_finished round_cancelled]],
  [GameRoomGames::QuizParty.new, %w[round_draw round_category question answer_commit answers_closed answer_nonce answer_pick question_finished]]
].each do |game, actions|
  options = game.default_options
  initial = game.send(:initial_state, %w[Alice Bob Carol], options)
  actions.each do |action|
    state = GameRoomSnapshot.copy(initial)
    history = []
    frame = GameRoomReduction::Frame.new(state: state, players: state[:players], options: options, history: history, draw: false)
    before = GameRoomTest::ContractValues.digest(frame)
    event = GameRoomReduction::Event.new(action: action, actor: 'Outsider', id: 7, value: 'invalid', timestamp: 100, source: {})
    assert(!game.send(:apply_replay_event, frame, event), "#{game.id}: unauthorized #{action} accepted")
    assert_equal(before, GameRoomTest::ContractValues.digest(frame), "#{game.id}: rejected #{action} changed state/history")
  end
end

game = GameRoomGames::Uno.new
state = game.send(:initial_state, %w[Alice Bob], game.default_options)
before = Marshal.dump(state)
assert(game.send(:validated_play, state, {'value' => 'invalid|red|1'}, 'Outsider').nil?, 'invalid UNO play was planned')
assert_equal(before, Marshal.dump(state), 'UNO validation mutated its input')
puts 'PASS rejected transitions preserve state, history and private phase data'
