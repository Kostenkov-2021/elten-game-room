if ARGV.delete("--binary")
  require_relative "support/binary_rules_load"
  BinaryRulesLoad.load(File.expand_path(__FILE__))
  exit
end
require_relative "support/ui"
require_relative "../lib/game_screen"
require_relative "support/new_games_fixture"
require_relative "../games/ninety_nine"
require_relative "../games/ludo"
module Session
  def self.name; "Alice"; end
end

def spoken_result(game, replay, repo, event)
  screen = GameScreen.allocate
  screen.instance_variable_set(:@game, game)
  screen.instance_variable_set(:@repository, repo)
  screen.instance_variable_set(:@surface_state, {})
  program = Object.new
  def program.game_room_sound_volume(_name); 0.0; end
  screen.instance_variable_set(:@program, program)
  spoken = []
  screen.define_singleton_method(:speak) { |text, **_| spoken << text }
  screen.send(:present_game_event, event, nil, replay, replay, nil)
  screen.send(:present_game_result, replay, nil)
  assert(spoken.count { |text| text == game.result_text(replay) } == 1, "#{game.id}: duplicate/missing winner")
  spoken
end

players = %w[Alice Bob]
repo = NewGames116Repository.new(players)
game = GameRoomGames::Mancala.new
state = game.send(:initial_state, players, game.normalize_options("variant"=>"kalah"))
state[:pits] = [0,0,0,0,0,1,20,2,0,0,0,0,0,25]
history = []
event = {"id"=>1,"actor"=>"Alice","action"=>"sow","value"=>"5"}
assert(game.send(:apply_sow, state, event, "Alice", repo, history), "Kalah move")
replay = game.wrap(players, state, [event], history)
assert(replay.finished? && replay.winner == "Bob", "Kalah scoring changed")
spoken = spoken_result(game, replay, repo, event)
assert(history.none? { |e| e.kind == :again } && spoken.none? { |t| t.include?("sows again") }, "extra turn after finish")
assert(history.count { |e| e.text == game.result_text(replay) } == 1, "winner removed from history")

game = GameRoomGames::NinetyNine.new
state = game.send(:initial_state, players, game.default_options)
state.merge!(phase: :playing, current_player: "Alice", total: 30,
  hands: {"Alice"=>%w[03C 04C 05C],"Bob"=>%w[06D 07D 08D]}, tokens: {"Alice"=>9,"Bob"=>0})
event = {"id"=>20,"actor"=>"Alice","action"=>"play","value"=>"03C|normal"}
history = []
assert(game.send(:apply_play, state, event, "Alice", repo, history), "99 move")
replay = GameRoomGames::Replay.new(players: players, current_player: state[:current_player], winner: state[:winner],
  draw: false, state: state, accepted_events: [event], history: history)
assert(replay.finished?, "99 did not finish")
spoken_result(game, replay, repo, event)
assert(history.count { |e| e.text == game.result_text(replay) } == 1, "99 history lost winner")

game = GameRoomGames::Ludo.new
# This regression needs a pass on one, not the newer default exit-on-one rule.
session = {"options"=>JSON.generate(game.normalize_options("enter_on_one"=>false))}
events = [{"id"=>1,"actor"=>"Alice","action"=>"roll","value"=>"1"}]
replay = game.replay(session, events, repo)
assert(replay.state[:roll] == nil && replay.current_player == "Bob", "Ludo turn did not advance")
assert(game.shortcut_feature_data(:last_roll, replay, "Alice")[:message] == "Alice, 1.", "D forgot passed roll or its author")
events << {"id"=>2,"actor"=>"Bob","action"=>"roll","value"=>"6"}
replay = game.replay(session, events, repo)
assert(game.shortcut_feature_data(:last_roll, replay, "Alice")[:message] == "Bob, 6.", "D did not update to opponent's roll and author")
fresh = game.replay(session, [], repo)
assert(game.shortcut_feature_data(:last_roll, fresh, "Alice")[:message] == "The dice have not been rolled.", "new game kept roll")
puts "PASS audit results: Kalah and 99 winner once/history retained, no false extra turn, Ludo D after pass/new roll/new game"
