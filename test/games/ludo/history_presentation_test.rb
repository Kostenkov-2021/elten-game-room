require_relative "../../support/new_board_games"
require_relative "../../../lib/participant_replay"

game = GameRoomGames::Ludo.new
repo = NewGamesRepository.new(%w[Alice Bob Carol Dave])
session = {'options' => JSON.generate(game.default_options)}
history = game.replay(session, [], repo).history
state = game.send(:initial_state, repo.players_for(session), game.default_options)
events = []
roll = lambda do |value, actor = state[:current_player]|
  event = {'id'=>events.length+1, 'actor'=>actor, 'action'=>'roll', 'value'=>value.to_s}
  events << event
  assert(game.send(:apply_roll!, state, event, actor, repo, history), 'roll rejected')
end
roll.call(1)
game.send(:apply_pawn_move_index!, state, 'Alice', 0, 0, 1, history)
roll.call(2) # Bob cannot leave the base.
roll.call(6, 'Carol')
game.send(:apply_pawn_move_index!, state, 'Carol', 2, 0, 3, history)
roll.call(6, 'Carol')
game.send(:apply_pawn_move_index!, state, 'Carol', 2, 0, 4, history)
roll.call(6, 'Carol') # Third six loses the turn.
# Multiple captures, then entry into the home lane and the finish.
state[:current_player] = 'Alice'
state[:pawns] = [[0, -1, -1, -1], [40,40,-1,-1], [-1]*4, [-1]*4]
state[:roll] = 1
game.send(:apply_pawn_move_index!, state, 'Alice', 0, 0, 6, history)
state[:current_player] = 'Alice'
state[:pawns][0] = [51,57,57,57]
state[:roll] = 1
game.send(:apply_pawn_move_index!, state, 'Alice', 0, 0, 7, history)
state[:current_player] = 'Alice'
state[:roll] = 5
game.send(:apply_pawn_move_index!, state, 'Alice', 0, 0, 8, history)
replay = GameRoomGames::Replay.new(players:state[:players],state:state,board:state[:pawns],winner:'Alice',history:history,accepted_events:events)
before = Marshal.dump(history)
names = game.history_entries_for_display(replay, 'Observer', surface_state:{'player_labels'=>'names'}).map(&:text)
colours = game.history_entries_for_display(replay, 'Observer', surface_state:{'player_labels'=>'colours'}).map(&:text)
assert(names.include?('Alice, from the base to track 1.'), 'base move missing')
assert(names.include?('Bob: no legal move.'), 'pass missing')
assert(colours.include?('yellow: three consecutive sixes; end of turn.'), 'three sixes lost colour')
assert(colours.include?('red, from track 52 to home lane 1.'), 'home entry missing')
assert(colours.include?('red, from home lane 1 to the finish.'), 'finish move missing')
assert(colours.last == 'red won the game.', 'winner lost colour')
assert(colours.any? { |s| s.include?('red: captured blue, from track 2;') && s.end_with?('Capture 2 of 2.') }, 'capture position/count/opponent wrong')
assert(colours.none? { |s| s.include?('pawn') || s.include?('Alice') || s.include?('Carol') }, 'nick/pawn escaped colour formatting')
assert(Marshal.dump(history) == before, 'local display changed original history')

# Historical author/seat must not be resolved against the current roster.
replay.players = %w[Replacement Bob Carol Dave]
replay.state = state.merge(players:replay.players)
assert(game.history_entries_for_display(replay, 'Observer', surface_state:{'player_labels'=>'colours'}).map(&:text) == colours, 'replacement changed historical colour')
assert(game.history_entries_for_display(replay, 'Observer', surface_state:{'player_labels'=>'names'}).map(&:text) == names, 'replacement renamed history')
game.board_presentation_preferences = {'player_labels'=>'colours'}
assert(game.history_entries_for_display(replay, 'Observer').map(&:text) == colours, 'stored preference not used before surface creation')
assert(game.describe_event_for_display(events.first, repo, replay, 'Observer') == ['red rolled 1.', 'red, from the base to track 1.'], 'speech differs from display')
replay.winner = nil
replay.current_player = 'Bob'
turn = game.turn_transition_history_entry(nil, replay, event_id:9)
replay.history = [turn]
assert(game.history_entries_for_display(replay,'Observer').first.text == 'Turn: blue.', 'turn history lost colour')
assert(game.turn_announcement(replay,'Alice') == 'Turn: blue.', 'automatic turn lost colour')
assert(game.turn_announcement(replay,'Bob') == 'It is your turn.', 'own turn changed')
catalog = GameRoomLocalization::Catalog.new(File.binread(File.expand_path("../../../locale/PL.mo", __dir__)))
assert(catalog.translate('from track %{position}') % {position:5} == 'z toru 5', 'Polish case is wrong')
assert(catalog.translate('Turn: %{player}.') % {player:'czerwony'} == 'Ruch: czerwony.', 'player prefix remains')
puts 'PASS Ludo history: roll/manual+automatic move/pass/three sixes/captures/home/finish/result/turn, historical seats, unchanged canonical history, PL/EN'
