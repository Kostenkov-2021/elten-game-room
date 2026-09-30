require_relative "../../support/audio_ball_point_audio"

module AudioBallPointTest
  check('accepted point immediately plays the real Pong goal effect and goal announcer') do
    program = Program.new
    spoken = []
    audio = GameRoomAudioBall::Audio.new(program, speaker: ->(text) { spoken << text })
    audio.point([2, 1], sets: [0, 0], set_finished: false, winner: 0, viewer: 0, finished: false)
    names = program.events.map(&:first)
    assert(names.count { |name| name.match?(/\Apong_goal[1-8]\z/) } == 1,
      'Accepted Audio Ball point did not play an original Pong goal effect immediately')
    assert(names.count { |name| name.match?(/\Apong_score[1-4]\z/) } == 1,
      'Accepted Audio Ball point did not play an original Pong goal voice immediately')
    assert(spoken.empty?, 'TTS spoke the score over the goal announcer')
    audio.close
  end
  check('an agreed preview plays once and a delayed durable point reuses its pause') do
    [0.8, 4.0].each do |delay|
      program, spoken = Program.new, []
      audio = GameRoomAudioBall::Audio.new(program, clock: -> { program.now }, speaker: ->(text) { spoken << text })
      audio.goal(viewer: 0, winner: 0)
      goals = program.events.map(&:first)
      assert(goals.length == 2 && !audio.presents_point, 'Preview announced a score or omitted goal recordings')
      program.now = delay
      audio.tick
      assert(program.events.map(&:first) == goals && spoken.empty?, 'Preview invented a score before durable confirmation')
      audio.point([1, 0], sets: [0, 0], set_finished: false, winner: 0, viewer: 0, finished: false, goal_at: 0.0)
      assert(program.events.map(&:first) == goals, 'Durable confirmation repeated the goal')
      program.now = [3.0, delay].max
      audio.tick
      assert(program.events.last.first == 'pong_scores', 'Accepted score restarted the elapsed three-second pause')
      assert(goals.all? { |name| program.events.count { |event| event.first == name } == 1 }, 'Preview or commit duplicated a goal recording')
      audio.close
    end
  end
  check('recorded scores share Pong scheduling and announce own score first after three seconds') do
    assert(GameRoomAudioBall::Audio.instance_methods.include?(:tick), 'Audio Ball cannot advance the Pong score queue')
    [0, 1, nil].each do |viewer|
      program, spoken = Program.new, []
      audio = GameRoomAudioBall::Audio.new(program, clock: -> { program.now }, rng: Random.new(17),
        speaker: ->(text) { spoken << text })
      assert(GameRoomAudioBall::PointAudio.superclass == Object, 'Audio Ball still inherits unrelated Pong effects and preferences')
      # A selected sound pack can replace the goal effect; the default
      # pack's exact random effect/voice is checked below.
      [:point, :advance_score_queue, :retire_announcements].each do |method|
        assert(GameRoomAudioBall::PointAudio.instance_method(method).owner == GameRoomRealtime::ScoreAnnouncements,
          "Audio Ball diverged from the shared #{method} implementation")
      end
      expected = GameRoomAudioBall::Audio::ASSETS + GameRoomRealtime::ScoreAnnouncements::ANNOUNCEMENTS
      assert(program.created.map(&:first) == expected, 'Point audio loaded paddle, crowd or echo assets / omitted a recording')
      assert(program.created.drop(GameRoomAudioBall::Audio::ASSETS.length).all? { |_, sample, loop| !sample && !loop }, 'Point audio must use non-looping host streams')
      audio.load
      assert(program.created.length == expected.length, 'Repeated load leaked announcement handles')
      audio.point([2, 1], sets: [0, 0], set_finished: false, winner: 0, viewer: viewer, finished: false)
      random = Random.new(17)
      expected_goal = [GameRoomRealtime::ScoreAnnouncements::GOALS[random.rand(8)], GameRoomRealtime::ScoreAnnouncements::GOAL_VOICES[random.rand(4)]]
      assert(program.events.map(&:first) == expected_goal, 'Audio Ball changed original goal variant selection')
      program.now = 2.999
      audio.tick
      assert(program.events.length == 2, 'Score started before the original three-second minimum')
      program.now = 3.0
      audio.tick
      assert(program.events.last.first == 'pong_scores', 'Missing the original recorded score introduction')
      audio.tick
      assert(program.events.length == 3, 'One tick overlapped the introduction and a number')
      program.now = 3.5
      audio.tick
      program.now = 4.0
      audio.tick
      numbers = viewer == 1 ? %w[pong_number1 pong_number2] : %w[pong_number2 pong_number1]
      assert(program.events.map(&:first) == expected_goal + ['pong_scores'] + numbers, 'Recorded point order is wrong')
      assert(spoken.empty?, 'TTS duplicated the recorded score')
      audio.close
    end
  end
  check('final set and match speech waits for complete numbers and queues the next set and server') do
    program, spoken, speaking = Program.new, [], false
    audio = GameRoomAudioBall::Audio.new(program, clock: -> { program.now },
      speaker: ->(text) { spoken << [text, program.now]; speaking = true }, speech_active: -> { speaking })
    program.sounds.fetch('pong_number7').duration = 2.0
    audio.point([7, 5], sets: [3, 1], set_finished: true, winner: 0, viewer: 1, finished: true)
    assert(spoken.empty?, 'Final result speech overlapped the goal announcer')
    audio.announce_set(2)
    audio.announce('Alice serves.')
    assert(spoken.empty?, 'Next-set/server speech cut into pending point recordings')
    [3.0, 3.5, 4.0].each { |now| program.now = now; audio.tick }
    assert(program.events.last.first == 'pong_number7', 'Final pre-reset score was lost')
    program.now = 5.7
    audio.tick
    assert(spoken.empty? && program.sounds['pong_number7'].playing?, 'Final number was cut off by match or next-set speech')
    program.now = 6.0
    audio.tick
    assert(spoken.map(&:first) == ['You lose the set. Sets: 1 to 3. You lose the match.'], 'Final result omitted sets or winner perspective')
    program.now = 7.0
    audio.tick
    assert(spoken.length == 1, 'Next set overlapped active result synthesis')
    speaking = false
    audio.tick
    assert(spoken.last.first == 'Second set.', 'Next set was lost behind the final result')
    speaking = false
    audio.tick
    assert(spoken.last.first == 'Alice serves.', 'Server status bypassed the ordered speech queue')
    assert(program.sounds['pong_number7'].interruptions.zero?, 'Set/match announcement truncated the final recording')
    audio.close
  end
  check('presents_point tells the screen when recordings or fallback replace its text announcement') do
    assert(GameRoomAudioBall::Audio.instance_methods.include?(:presents_point), 'Audio Ball does not expose point presentation status')
    [[], ['pong_number2']].each do |missing|
      program, spoken = Program.new(missing: missing), []
      audio = GameRoomAudioBall::Audio.new(program, clock: -> { program.now }, speaker: ->(text) { spoken << text })
      assert(audio.presents_point == false, 'A fresh audio object claims to present a point')
      audio.point([2, 1], sets: [0, 0], set_finished: false, winner: 0, viewer: 0, finished: false)
      assert(audio.presents_point == true, 'Screen would duplicate a recorded or queued fallback score')
      [:enabled, :gain].each do |setting|
        audio.point([2, 1], sets: [0, 0], set_finished: false, winner: 0, viewer: 0, finished: false)
        program.send("#{setting}=", setting == :enabled ? false : 0)
        audio.tick
        assert(audio.presents_point == false, 'Muting still suppresses the screen text fallback')
        assert(program.sounds.values.none?(&:playing?), 'Mute left a point stream running')
        audio.point([7, 5], sets: [3, 0], set_finished: true, winner: 0, viewer: 0, finished: true)
        assert(audio.presents_point == false && spoken.empty?, 'Muted point competed with the screen full-result fallback')
        program.send("#{setting}=", setting == :enabled ? true : 1.0)
        count = program.events.length
        program.now += 10
        audio.tick
        assert(program.events.length == count && spoken.empty? && !audio.presents_point, 'Unmuting replayed an obsolete presentation')
      end
      program.enabled = false
      audio.announce_set(1)
      audio.hurry('Alice')
      assert(spoken == ['First set.', 'Alice, you have 10 seconds left.'], 'Muting sound effects silenced ordinary Elten status speech')
      audio.close
      assert(audio.presents_point == false, 'Closed audio still claims to present a point')
    end
  end
  check('fallback reads the entire ordered score for deuce or any missing required recording') do
    cases = [[[22, 21], []], [[21, 22], []], [[22, 22], []], [[99, 0], []]]
    cases += %w[pong_scores pong_number2 pong_number1].map { |name| [[2, 1], [name]] }
    cases += [[[2, 1], GameRoomRealtime::ScoreAnnouncements::ANNOUNCEMENTS]]
    cases.each do |scores, missing|
      [0, 1, nil].each do |viewer|
        program, spoken = Program.new(missing: missing), []
        audio = GameRoomAudioBall::Audio.new(program, clock: -> { program.now }, speaker: ->(text) { spoken << text })
        audio.point(scores, sets: [0, 0], set_finished: false, winner: 0, viewer: viewer, finished: false)
        program.now = 2.99
        audio.tick
        assert(spoken.empty?, 'Fallback spoke before the goal pause')
        program.now = 3.0
        audio.tick
        ordered = viewer == 1 ? scores.reverse : scores
        assert(spoken == ["Score: #{ordered[0]} to #{ordered[1]}."], 'Missing/range fallback announced only one score or the wrong order')
        assert(program.events.none? { |name, *_| name == 'pong_scores' || name.start_with?('pong_number') },
          'An incomplete recorded score mixed with fallback synthesis')
        audio.close
      end
    end
  end

  check('a missing goal variant uses the original generic goal and still reads recorded 21 to 21') do
    program = Program.new(missing: GameRoomRealtime::ScoreAnnouncements::GOALS)
    spoken = []
    audio = GameRoomAudioBall::Audio.new(program, clock: -> { program.now }, speaker: ->(text) { spoken << text })
    audio.point([21, 21], sets: [0, 0], set_finished: false, winner: 0, viewer: 0, finished: false)
    assert(program.events.first.first == 'pong_goal', 'Missing variant silenced the original generic goal fallback')
    [3.0, 3.5, 4.0, 4.5].each { |now| program.now = now; audio.tick }
    assert(program.events.map(&:first).last(3) == %w[pong_scores pong_number21 pong_number21], 'The recorded upper boundary was lost or repeated number cut itself off')
    assert(program.sounds['pong_number21'].interruptions.zero? && spoken.empty?, 'A valid recorded pair used fallback or truncated a number')
    audio.close
  end

  check('slow ticks never overlap or truncate recorded voices') do
    program, spoken = Program.new, []
    audio = GameRoomAudioBall::Audio.new(program, clock: -> { program.now }, speaker: ->(text) { spoken << text })
    GameRoomRealtime::ScoreAnnouncements::ANNOUNCEMENTS.each { |name| program.sounds[name].duration = 2.0 }
    GameRoomRealtime::ScoreAnnouncements::GOAL_VOICES.each { |name| program.sounds[name].duration = 5.0 }
    audio.point([2, 1], sets: [0, 0], set_finished: false, winner: 0, viewer: 0, finished: false)
    program.now = 3.0
    audio.tick
    assert(program.events.length == 2, 'Score interrupted a long goal announcer at the three-second boundary')
    [10.0, 10.0, 10.1, 12.0, 13.0, 14.0, 16.0].each { |now| program.now = now; audio.tick }
    voices = program.events.reject { |name, *_| GameRoomRealtime::ScoreAnnouncements::GOALS.include?(name) }
    assert(voices.drop(1).map { |name, at, _| [name, at] } == [['pong_scores', 10.0], ['pong_number2', 12.0], ['pong_number1', 14.0]],
      'A delayed tick skipped spacing or played several overdue voices at once')
    voices.each_cons(2) { |(_, at, length), (_, next_at, _)| assert(next_at >= at + length, 'Recorded voices overlap') }
    assert(program.sounds.values.all? { |sound| sound.interruptions.zero? }, 'Queue truncated a still-playing voice')
    assert(spoken.empty? && program.sounds.values.none?(&:playing?), 'Completed recorded queue left speech/streams running')
    audio.close
  end

  check('announcement mix uses original half gain and shared volume, independent of Pong preferences') do
    program = Program.new
    program.gain, program.announcer = 0.4, 80
    audio = GameRoomAudioBall::Audio.new(program, clock: -> { program.now }, speaker: ->(_) {})
    audio.point([2, 1], sets: [0, 0], set_finished: false, winner: 0, viewer: 0, finished: false)
    check_mix = lambda do
      program.sounds.values.select(&:playing?).each do |sound|
        assert((sound.volume - 0.5 * program.gain).abs < 0.000001, 'Audio Ball ignored category gain or inherited personal Pong volume')
        assert(sound.pan == 0 && sound.frequency == 48_000, 'Non-positional announcer was mirrored or pitch-shifted')
      end
    end
    check_mix.call
    program.gain, program.announcer = 0.7, 0
    audio.tick
    check_mix.call
    [3.0, 3.5, 4.0].each { |now| program.now = now; audio.tick; check_mix.call }
    audio.close
  end

  check('reset view detachment and final presentation keep the point queue but close cancels everything') do
    program, spoken = Program.new, []
    audio = GameRoomAudioBall::Audio.new(program, clock: -> { program.now }, speaker: ->(text) { spoken << text })
    flight = {'phase' => 'flying', 'shot' => 'up', 'turn' => 1, 'position' => 25.0}
    audio.update(flight, viewer: 0)
    audio.point([7, 5], sets: [3, 1], set_finished: true, winner: 0, viewer: nil, finished: true)
    assert(!program.sounds['audio_ball_up'].playing?, 'A point left flight playing')
    audio.announce_set(2)
    [nil, {'phase' => 'over'}, flight].each do |snapshot|
      audio.reset
      audio.silence
      audio.update(snapshot, viewer: 0, paused: true)
      assert(program.events.select { |name, *_| GameRoomRealtime::ScoreAnnouncements::ANNOUNCEMENTS.include?(name) }.take(2).all? { |name, *_| program.sounds[name].playing? }, 'Reset/detach cut the goal announcement')
    end
    [3.0, 3.5, 4.0].each do |now|
      program.now = now
      audio.tick
      name = program.events.last.first
      before = program.sounds[name].seeks.dup
      audio.prepare(0, viewer: 0)
      audio.update(flight, viewer: 0)
      audio.reset
      assert(program.sounds[name].playing? && program.sounds[name].seeks == before, 'Preparation/new flight/reset stopped or rewound a score number')
    end
    program.now = 4.5
    audio.tick
    assert(spoken == ['Player 1 wins the set. Sets: 3 to 1. Player 1 wins the match.'], 'Observer final result was missing or used a player win voice')
    count = program.events.length
    audio.close
    audio.close
    program.now = 100
    audio.tick
    audio.load
    audio.reset
    audio.announce('Stale server.')
    audio.announce_set(3)
    audio.hurry('Alice')
    audio.point([1, 0], sets: [0, 0], set_finished: false, winner: 0, viewer: 0, finished: false)
    assert(spoken.length == 1 && program.events.length == count, 'Close revived queued/late speech or sounds')
    assert(program.managed == program.released, 'Close leaked or double-released reused Pong handles')
    assert(program.sounds.values.all? { |sound| sound.closes == 1 && !sound.playing? }, 'Close did not dispose of every flight and announcement handle')
  end

  check('Pong recordings are reused from both original manifests without duplicate assets') do
    require 'json'
    root = File.expand_path("../../..", __dir__)
    source = File.read(File.join(root, '__app.rb'), encoding: 'UTF-8')
    manifests = [JSON.parse(File.read(File.join(root, 'manifest.json'), encoding: 'UTF-8')),
      JSON.parse(source.split('=begin Elten3AppInfo', 2).last.split('=end Elten3AppInfo', 2).first)]
    GameRoomRealtime::ScoreAnnouncements::ANNOUNCEMENTS.each do |name|
      manifests.each { |manifest| assert(manifest.fetch('required_assets').fetch('sounds').count(name) == 1, "Missing/duplicated shared recording: #{name}") }
      path = File.join(root, 'Audio', "#{name}.opus")
      assert(File.binread(path, 128).include?('OpusHead'), "Shared Pong recording is not shipped as Opus: #{name}")
    end
  end
end

puts 'PASS Audio Ball point audio (fake host handles; no device playback)'
