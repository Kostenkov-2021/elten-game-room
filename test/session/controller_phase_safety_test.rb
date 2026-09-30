require_relative "../support/native_room_harness"
require_relative "../../games/quiz_party"
require_relative "../../games/categories"
require_relative "../../games/battleship"
require_relative "../../games/krowa"
require_relative "../../games/scrabble"
require_relative "../../games/uno"
require_relative "../../games/axel_pong"
require_relative "../../games/audio_ball"

ReplayPhase = Struct.new(:state, :done) do
  def finished?; done == true; end
end
%w[QuizParty Categories].each do |name|
  game = GameRoomGames.const_get(name).new
  %i[answering revealing].each do |phase|
    assert(game.controller_change_error(ReplayPhase.new({phase: phase}, false)), "#{game.id}: private phase was transferable")
    assert(game.controller_change_error(ReplayPhase.new({phase: phase}, false), replacement: true), "#{game.id}: private answers replaced")
  end
  assert(game.controller_change_error(ReplayPhase.new({phase: :round_complete}, false)) == nil, "#{game.id}: public boundary was blocked")
end
[GameRoomGames::Battleship.new, GameRoomGames::Krowa.new].each do |game|
  assert(game.controller_change_error(ReplayPhase.new({phase: :playing}, false)), "#{game.id}: lost private game allowed")
  assert(game.controller_change_error(ReplayPhase.new({phase: :finished}, true)) == nil, "#{game.id}: finished game blocks room transfer")
end
game = GameRoomGames::Scrabble.new
assert(game.controller_change_error(ReplayPhase.new({}, false), replacement: true), 'Game without a bot accepted replacement')
[GameRoomGames::Uno.new, GameRoomGames::AxelPong.new, GameRoomGames::AudioBall.new].each do |game|
  assert(game.controller_change_error(ReplayPhase.new({}, false), replacement: true) == nil, "#{game.id}: normal replacement blocked")
end
puts 'Controller changes: private phases wait, public boundaries and realtime supported, no invented bots: OK'
