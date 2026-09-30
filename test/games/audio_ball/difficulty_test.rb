require_relative "../../support/audio_ball_client"

expected = [[1, 4.0, 1.05], [2, 2.2, 1.05], [3, 1.5, 1.05], [4, 0.9, 1.05], [5, 0.6, 1.05]]
assert(GameRoomAudioBall::Bot::ERROR_CHANCE == [0.32, 0.24, 0.11, 0.06, 0.025], 'wrong-defense probabilities differ from the agreed five levels')
game = GameRoomGames::AudioBall.new
choices = game.option_definitions.find { |definition| definition.key == 'difficulty' }.choices
assert(choices.map(&:value) == [1, 2, 3, 4, 5], 'table creation does not offer five difficulty levels')
assert(game.default_options['difficulty'] == 3 && choices[2].label == 'Normal', 'default difficulty is not Normal')
expected.each do |level, initial, factor|
  assert(game.normalize_options('difficulty' => level)['difficulty'] == level, 'a valid difficulty was normalized to another level')
  [0, 1].each do |server|
    engine = GameRoomAudioBall::Engine.new(level: level, server: server)
    12.times do |hit|
      side = engine.holder
      assert(engine.press(side, 'prepare') && engine.press(side, 'up'), 'difficulty prevented a prepared hit')
      duration = initial / factor**hit
      assert((engine.duration - duration).abs < duration * 1e-10, "level #{level} hit #{hit + 1} has the wrong full-flight duration")
      restored = GameRoomAudioBall::Engine.new
      assert(restored.restore(engine.snapshot), 'the difficulty snapshot cannot round-trip through another engine')
      assert(restored.level == level && restored.duration == engine.duration, 'restoring a snapshot changed its level or speed')
      engine.step(engine.duration * 0.96)
      assert(engine.press(engine.receiver, engine.shot), 'difficulty prevented a legal matching defense')
    end
    assert(GameRoomAudioBall::Engine.new(level: level, server: server).duration == initial, 'a new rally did not reset the initial speed')
    bot = GameRoomAudioBall::Bot.new(server, level: level, rng: Random.new(17))
    engine = GameRoomAudioBall::Engine.new(level: level, server: server)
    assert(bot.step(engine, seconds: 1.0) && engine.phase == :prepared, 'bot cannot prepare at this difficulty')
    assert(bot.step(engine, seconds: 1.0) && engine.phase == :flying, 'bot cannot attack at this difficulty')
  end
  h = AudioBallHarness.new(options: {'difficulty' => level})
  h.advance(12)
  h.press('Alice', 'prepare', 'left')
  h.advance(3)
  assert(h.clients.values.all? { |client| client.engine.level == level && client.engine.duration == initial }, 'clients disagree about the selected difficulty or initial speed')
  h.close
end
[GameRoomAudioBall::Bot::HOLD_DELAY, GameRoomAudioBall::Bot::REACTION_TIME,
  GameRoomAudioBall::Bot::ERROR_CHANCE].each do |values|
  assert(values.length == 5 && values.each_cons(2).all? { |a, b| a > b }, 'bot levels are not progressively harder')
end
100.times do |hits|
  durations = expected.map { |_level, initial, factor| initial / factor ** hits }
  assert(durations.each_cons(2).all? { |a, b| a > b }, 'harder level became easier in a long rally')
end
assert(game.normalize_options('difficulty' => 6)['difficulty'] == 3, 'an unsupported difficulty was accepted')
puts 'PASS Audio Ball five difficulties: durations, monotonic speed/bots, both seats, snapshots, new rallies and client options'
