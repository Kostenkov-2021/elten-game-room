require_relative "../support/audio_ball_point_audio"

raise 'Audio Ball still loads Pong effects/preferences' if $LOADED_FEATURES.any? { |path| path.match?(%r{/axel_pong/(audio|audio_extras|preferences)\.rb\z}) }
raise 'Audio Ball point presenter acquired paddle controls' if GameRoomAudioBall::PointAudio.instance_methods.include?(:play_local_movement)

require_relative "../../lib/axel_pong/audio"

module AudioBallPointTest
  check('both presenters share only the sequencer and produce the same complete score trace') do
    traces = [GameRoomAudioBall::PointAudio, GameRoomPong::Audio].map do |type|
      program, spoken = Program.new, []
      program.gain = 0.7
      # Both use the same effective gain here; separate tests vary Pong's
      # personal slider and confirm it cannot change Audio Ball.
      audio = type.new(program, clock: -> { program.now }, rng: Random.new(81),
        speaker: ->(text) { spoken << [program.now, text] }, speech_active: -> { false })
      audio.load
      audio.point([7, 6], viewer: 0, winner: 0, finished: true)
      [0.0, 0.2, 3.0, 3.0, 3.5, 4.0, 5.7, 6.0, 6.2, 6.5, 7.0, 8.0].each do |at|
        program.now = at
        audio.tick
      end
      announcements = GameRoomRealtime::ScoreAnnouncements::ANNOUNCEMENTS
      trace = program.events.select { |name, *_| announcements.include?(name) }
      assert(trace.map(&:first).last(4) == %w[pong_youwin pong_scores pong_number7 pong_number6], 'Final victory/repeated score missing')
      assert(audio.instance_variable_get(:@score_queue).empty? && spoken.empty?, 'Completed queue retained work or duplicated recordings with speech')
      trace.each do |name, *_|
        sound = program.sounds.fetch(name)
        assert((sound.volume - 0.35).abs < 0.000001 && sound.pan == 0 && sound.frequency == 48_000, 'Score trace changed gain/pan/pitch')
      end
      audio.close
      [trace, spoken]
    end
    assert(traces[0] == traces[1], 'Audio Ball and Pong score scheduling diverged')
    [:point, :advance_score_queue, :retire_announcements, :play_voice].each do |name|
      owners = [GameRoomAudioBall::PointAudio, GameRoomPong::Audio].map { |type| type.instance_method(name).owner }
      assert(owners == [GameRoomRealtime::ScoreAnnouncements] * 2, 'Score algorithm was copied into a presenter')
    end
  end
end

module AudioBallPointTest
  check('muted background speech does not wait for unrelated host speech') do
    program = Program.new
    audio = GameRoomAudioBall::PointAudio.new(program, clock: -> { program.now },
      speaker: ->(_text) { false }, speech_active: -> { true })
    audio.load
    audio.point([22, 21], viewer: 0, winner: 0, finished: true, result_text: 'won')
    [3.0, 3.5, 4.0, 5.7, 6.5, 8.0].each { |time| program.now = time; audio.tick }
    assert(!audio.instance_variable_get(:@speech_pending), 'Muted text still marked as speaking')
    assert(audio.instance_variable_get(:@score_queue).empty?, 'Muted text blocked later announcements')
    audio.close
  end
end

puts 'PASS standalone Audio Ball dependency boundary and complete shared score-sequencer trace (no device playback)'
