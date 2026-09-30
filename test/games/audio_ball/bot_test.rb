require_relative "../../../lib/audio_ball/engine"
require_relative "../../../lib/audio_ball/bot"

module AudioBallBotTest
  @tests = 0
  @assertions = 0

  class TracedEngine < GameRoomAudioBall::Engine
    attr_reader :presses

    def initialize(**options)
      super
      @presses = []
    end

    def press(side, command)
      before = snapshot
      accepted = super
      @presses << [side, command, before, accepted]
      accepted
    end
  end

  def self.assert(value, message)
    @assertions += 1
    raise message unless value
  end

  def self.equal(expected, actual, message)
    assert(expected == actual, "#{message}: expected #{expected.inspect}, got #{actual.inspect}")
  end

  def self.test(name)
    yield
    @tests += 1
    puts "PASS #{name}"
  end

  def self.simulate_match(level, frame, seed)
    bots = [0, 1].map { |side| GameRoomAudioBall::Bot.new(side, level: level, rng: Random.new(seed + side)) }
    scores = [0, 0]
    trace = []
    points = 0
    ticks = 0
    60.times do |rally|
      server = (rally / 2) % 2
      engine = GameRoomAudioBall::Engine.new(level: level, server: server)
      observer = GameRoomAudioBall::Engine.new(level: level, server: server)
      8000.times do
        bots.each { |bot| bot.step(engine, seconds: frame) }
        defenses = bots.each_with_object({}) { |bot, lanes| lanes[bot.side] = bot.selected_lane if bot.selected_lane }
        engine.step(frame, defenses: defenses)
        while (event = engine.take_transition)
          assert(observer.apply(event), 'observer rejected normal bot transition')
          trace << [rally, event['turn'], event['action'], event['side'], event['shot']]
        end
        ticks += 1
        break if engine.goal
      end
      assert(!engine.goal.nil?, 'bot rally exceeded bounded simulation')
      equal(engine.goal, observer.goal, 'bot point disagreed with observer')
      equal(engine.snapshot, observer.snapshot, 'bot point ended in divergent engine state')
      scores[engine.goal] += 1
      points += 1
      break if scores.max >= 7 && (scores[0] - scores[1]).abs >= 2
    end
    assert(scores.max >= 7 && (scores[0] - scores[1]).abs >= 2, 'bot match did not finish with two-point margin')
    {scores: scores, points: points, ticks: ticks, trace: trace}
  end

  def self.run
    test('Normal chooses a wrong defense only below the 11 percent threshold') do
      [0, 1].each do |side|
        GameRoomAudioBall::Engine::SHOTS.each do |shot|
          [0.0, 0.109999, 0.11, 0.139999, 0.999999].each do |roll|
            draws = [0.5, roll]
            rng = Object.new
            rng.define_singleton_method(:rand) { |limit = nil| limit ? 0 : draws.shift || raise('unexpected random draw') }
            engine = TracedEngine.new(level: 3, server: 1 - side)
            bot = GameRoomAudioBall::Bot.new(side, level: 3, rng: rng)
            engine.press(1 - side, 'prepare')
            engine.press(1 - side, shot)
            engine.step(engine.duration * 0.99, controlled: [])
            accepted = bot.step(engine, seconds: GameRoomAudioBall::Bot::REACTION_TIME[2])
            correct = roll >= 0.11
            equal(correct, accepted, "Normal defense threshold for roll #{roll}")
            equal(correct, engine.presses.last[1] == shot, 'bot selected an unexpected defense lane')
            equal(correct ? :waiting : :flying, engine.phase, 'threshold test changed the standard defense pathway')
            assert(draws.empty?, 'bot did not use the supplied distance and error decisions')
          end
        end
      end
    end
    test('an attack cannot arm the bot for an incoming flight') do
      [0, 1].each do |side|
        engine = TracedEngine.new(server: side)
        bot = GameRoomAudioBall::Bot.new(side, rng: Random.new(10))
        bot.step(engine, seconds: 1)
        bot.step(engine, seconds: 1)
        shot = engine.shot
        assert(GameRoomAudioBall::Engine::SHOTS.include?(shot), 'bot did not serve normally')
        equal(nil, bot.selected_lane, 'a bot attack armed its next defense')
        engine.step(engine.duration, defenses: {1 - side => shot})
        engine.press(1 - side, 'prepare')
        engine.press(1 - side, shot)
        lane = bot.selected_lane
        engine.step(engine.duration, controlled: [side], defenses: lane ? {side => lane} : {})
        equal(1 - side, engine.goal, 'bot defended a new flight without reacting to it')
      end
    end
    test('each repeated bot defense requires a new reaction even before the next bot step') do
      [0, 1].each do |side|
        rng = Object.new
        def rng.rand(limit = nil); limit ? 0 : 0.9; end
        engine = TracedEngine.new(server: 1 - side)
        bot = GameRoomAudioBall::Bot.new(side, rng: rng)
        engine.press(1 - side, 'prepare')
        engine.press(1 - side, 'up')
        bot.step(engine, seconds: GameRoomAudioBall::Bot::REACTION_TIME.first)
        engine.step(engine.duration * 0.95, controlled: [])
        assert(bot.step(engine, seconds: 0.01), 'bot did not make the initial matching reaction')
        equal(side, engine.holder, 'initial bot reaction did not defend')
        engine.press(side, 'prepare')
        engine.press(side, 'left')
        engine.step(engine.duration, defenses: {1 - side => 'left'})
        engine.press(1 - side, 'prepare')
        engine.press(1 - side, 'up')
        equal(nil, bot.selected_lane, 'a second identical flight reused the previous bot reaction')
        assert(!bot.step(engine, seconds: 0.01), 'new incoming flight bypassed bot reaction delay')
        equal(nil, bot.selected_lane, 'planning a new reaction armed the bot before its delay')
        engine.step(engine.duration * 0.95, controlled: [])
        assert(bot.step(engine, seconds: GameRoomAudioBall::Bot::REACTION_TIME.first), 'bot could not react afresh to the repeated shot')
      end
    end
    test('an armed bot choice belongs to its engine instance as well as its turn') do
      [0, 1].each do |side|
        rng = Object.new
        def rng.rand(limit = nil); limit ? 0 : 0.0; end
        bot = GameRoomAudioBall::Bot.new(side, rng: rng)
        engine = TracedEngine.new(server: 1 - side)
        engine.press(1 - side, 'prepare')
        engine.press(1 - side, 'down')
        engine.step(engine.duration * 0.99, controlled: [])
        assert(!bot.step(engine, seconds: GameRoomAudioBall::Bot::REACTION_TIME.first), 'error-strategy fixture unexpectedly caught the ball')
        equal('up', bot.selected_lane(engine), 'wrong reaction was not armed for its current flight')
        replacement = TracedEngine.new(server: 1 - side)
        replacement.press(1 - side, 'prepare')
        replacement.press(1 - side, 'up')
        equal(engine.turn, replacement.turn, 'engine replacement did not repeat a turn number')
        equal(nil, bot.selected_lane(replacement), 'new engine inherited another flight with the same turn')
        assert(!bot.step(replacement, seconds: 0.01), 'replacement flight skipped the reaction delay')
        equal(nil, bot.selected_lane(replacement), 'replacement flight retained the old armed choice')
      end
    end
    test('bot prepares then attacks through separate delayed presses') do
      [1, 2, 3, 4, 5].each do |level|
        [0, 1].each do |side|
          engine = TracedEngine.new(level: level, server: side)
          bot = GameRoomAudioBall::Bot.new(side, level: level, rng: Random.new(10))
          opponent = GameRoomAudioBall::Bot.new(1 - side, level: level, rng: Random.new(20))
          assert(!opponent.step(engine, seconds: 2), 'opponent bot took possession')
          assert(!bot.step(engine, seconds: 0.01), 'bot prepared without a reaction delay')
          equal(:waiting, engine.phase, 'bot skipped waiting')
          100.times do
            break if engine.phase == :prepared
            bot.step(engine, seconds: 0.01)
          end
          equal(:prepared, engine.phase, 'bot did not prepare within one second')
          equal([side, 'prepare'], engine.presses.last.first(2), 'bot bypassed prepare press')
          equal({'action' => 'prepare', 'side' => side, 'turn' => 1}, engine.take_transition, 'bot swallowed preparation transition')
          assert(!bot.step(engine, seconds: 0.01), 'bot attacked immediately after preparation')
          100.times do
            break if engine.phase == :flying
            bot.step(engine, seconds: 0.01)
          end
          equal(:flying, engine.phase, 'bot did not attack within one second')
          equal(2, engine.presses.length, 'bot bypassed or spammed press pathway')
          equal('hit', engine.take_transition['action'], 'bot swallowed hit transition')
          position = engine.position
          assert(!bot.step(engine, seconds: 3), 'sender bot tried to defend')
          equal(position, engine.position, 'bot advanced engine physics')
        end
      end
    end
    test('fresh lane decisions retain one late attempt and level-dependent accuracy') do
      counts = []
      [1, 2, 3, 4, 5].each do |level|
        defended = 0
        attempts = 0
        [0, 1].each do |side|
          rng = Random.new(1234 + side)
          200.times do |trial|
            bot = GameRoomAudioBall::Bot.new(side, level: level, rng: rng)
            engine = TracedEngine.new(level: level, server: 1 - side)
            engine.press(1 - side, 'prepare')
            engine.press(1 - side, %w[up left down][trial % 3])
            engine.take_transition
            engine.take_transition
            ((engine.duration / 0.01).ceil + 10).times do
              bot.step(engine, seconds: 0.01)
              break unless engine.phase == :flying
              defenses = bot.selected_lane ? {side => bot.selected_lane} : {}
              engine.step(0.01, defenses: defenses)
            end
            assert(engine.phase == :waiting || engine.phase == :over, 'defense flight did not finish')
            presses = engine.presses.drop(2)
            assert(presses.length <= 1, 'bot retried a mistaken defense in the same flight')
            presses.each do |actor, command, before, accepted|
              equal(side, actor, 'bot pressed for opponent')
              equal('flying', before['phase'], 'bot changed ball without a defensive press')
              endpoint = side == 0 ? 25.0 : 0.0
              assert((endpoint - before['position']).abs <= 2.0, 'bot used early future knowledge to defend')
              equal(before['shot'] == command, accepted, 'bot bypassed matching-shot validation')
              equal(nil, bot.selected_lane, 'a completed flight retained an armed bot lane')
            end
            attempts += presses.length
            transition = engine.take_transition
            equal(engine.phase == :waiting ? 'defend' : 'miss', transition['action'], 'bot did not leave standard outgoing transition')
            defended += 1 if engine.phase == :waiting
            equal(nil, engine.take_transition, 'bot duplicated defensive transition')
          end
        end
        assert(attempts > 350, 'bot rarely attempted a reachable defense')
        lower, upper = [[230, 305], [265, 345], [305, 380], [345, 397], [365, 400]][level - 1]
        assert(defended.between?(lower, upper), "level #{level} accuracy #{defended}/400 is not fair")
        counts << defended
      end
      assert(counts.each_cons(2).all? { |easier, harder| easier < harder }, 'bot difficulty does not improve defense')
      puts "Defense successes per 400 flights: #{counts.join(', ')}"
    end
    test('invalid bot configuration and time cannot poison a later decision') do
      [nil, -1, 2, '0', 0.0, true].each do |side|
        begin
          GameRoomAudioBall::Bot.new(side, level: 1)
          assert(false, 'invalid bot side accepted')
        rescue ArgumentError
          assert(true, 'invalid side rejected')
        end
      end
      [nil, 0, 6, '1', 1.0, true].each do |level|
        begin
          GameRoomAudioBall::Bot.new(0, level: level)
          assert(false, 'invalid bot level accepted')
        rescue ArgumentError
          assert(true, 'invalid level rejected')
        end
      end
      engine = TracedEngine.new
      bot = GameRoomAudioBall::Bot.new(0, level: 1, rng: Random.new(15))
      [nil, -1, '0.1', Float::NAN, Float::INFINITY, true].each do |seconds|
        begin
          bot.step(engine, seconds: seconds)
          assert(false, 'invalid bot time accepted')
        rescue ArgumentError
          equal(0, engine.turn, 'invalid bot time caused an action')
        end
      end
      assert(bot.step(engine, seconds: 1), 'bad time poisoned subsequent valid bot action')
      equal(:prepared, engine.phase, 'bot could not recover after rejected arguments')
    end
    test('bounded complete matches remain legal across difficulties and frame sizes') do
      matches = points = ticks = defenses = 0
      winners = [0, 0]
      [1, 2, 3, 4, 5].each do |level|
        [0.01, 0.017, 0.025, 0.05].each do |frame|
          [7, 43, 111, 901].each do |seed|
            result = simulate_match(level, frame, seed)
            matches += 1
            points += result[:points]
            ticks += result[:ticks]
            defenses += result[:trace].count { |row| row[2] == 'defend' }
            winners[result[:scores][0] > result[:scores][1] ? 0 : 1] += 1
          end
        end
      end
      assert(defenses > matches, 'complete-match tests did not exercise real rallies')
      assert(winners.all? { |count| count > 0 }, 'all seeded matches favor one side')
      puts "Completed #{matches} matches, #{points} points, #{defenses} defenses, #{ticks} frames; wins #{winners.inspect}"
    end
    test('seeded bot matches replay identically and bot reuse resets each point') do
      first = simulate_match(2, 0.02, 777)
      second = simulate_match(2, 0.02, 777)
      equal(first, second, 'seeded bot decisions are not reproducible')
      first[:trace].group_by(&:first).each do |_rally, actions|
        equal(1, actions[0][1], 'new point kept previous turn')
        equal('prepare', actions[0][2], 'new point did not require prepare')
        equal('hit', actions[1][2], 'new point did not attack after prepare')
      end
    end
    puts "PASS Audio Ball bot: #{@tests} tests, #{@assertions} assertions"
  end
end

AudioBallBotTest.run
