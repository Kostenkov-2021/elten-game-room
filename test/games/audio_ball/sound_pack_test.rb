require_relative "../../support/audio_ball_point_audio"

module AudioBallPointTest
  class Program
    attr_accessor :audio_preferences
    private
    def audio_ball_preferences
      @audio_preferences || GameRoomAudioBall::Preferences::DEFAULTS
    end
  end

  check('both packs map flight loops and one-shot prepare/stop with local pan and volume') do
    GameRoomAudioBall::SoundPack::PACKS.each do |id, pack|
      program = Program.new
      program.audio_preferences = {'listening_side' => 'right', 'sound_pack' => id}
      program.gain = 0.4
      audio = GameRoomAudioBall::Audio.new(program, clock: -> { program.now }, speaker: ->(*) {})
      %w[up left down].each_with_index do |shot, turn|
        sound = program.sounds.fetch(pack.fetch(shot))
        snapshot = {'phase' => 'flying', 'position' => 25.0, 'turn' => turn, 'shot' => shot}
        10.times { audio.update(snapshot, viewer: 0) }
        assert(sound.plays == 1 && sound.volume == 0.4 && sound.pan == 1, "#{id}: flight rewinds or loses pan/volume")
        assert(program.created.include?([pack[shot], false, true]), "#{id}: flight does not loop")
        program.audio_preferences['listening_side'] = 'left'
        audio.update(snapshot, viewer: 0)
        assert(sound.pan == -1 && sound.plays == 1, "#{id}: listening-side change restarts flight")
        program.audio_preferences['listening_side'] = 'right'
      end
      [0, 1].each do |viewer|
        [0, 1].each do |side|
          expected = (side == 0 ? 1 : -1) * (viewer == 1 ? -1 : 1)
          audio.prepare(side, viewer: viewer)
          ready = program.sounds.fetch(pack['prepare'])
          assert(ready.pan == expected && ready.volume == 0.4, "#{id}: prepare at wrong end")
          audio.stop_ball(side, viewer: viewer)
          stopped = program.sounds.fetch(pack['stop'])
          assert(stopped.pan == expected && stopped.volume == 0.4 && !ready.playing?, "#{id}: stop at wrong end or prepare overlaps")
          plays = stopped.plays
          10.times { audio.update({'phase' => 'waiting'}, viewer: viewer) }
          assert(stopped.plays == plays && stopped.playing?, "#{id}: waiting truncates or repeats stop cue")
          assert(program.created.include?([pack['stop'], false, false]), "#{id}: stop cue loops")
        end
      end
      program.enabled = false
      audio.stop_ball(0, viewer: 0)
      assert(program.sounds.values.none?(&:playing?), "#{id}: stop ignores mute")
      audio.close
      audio.close
      assert(program.sounds.values.all? { |sound| sound.closes == 1 }, "#{id}: leaking/double-closing resources")
      assert(program.managed == program.released, "#{id}: release order or managed ownership changed")
    end
  end

  check('switching packs changes only sounds, caches streams and preserves the queued score') do
    program = Program.new
    program.audio_preferences = {'listening_side' => 'right', 'sound_pack' => 'default'}
    audio = GameRoomAudioBall::Audio.new(program, clock: -> { program.now }, speaker: ->(*) {})
    snapshot = {'phase' => 'flying', 'position' => 12.5, 'turn' => 7, 'shot' => 'left'}
    original = snapshot.dup
    audio.update(snapshot, viewer: 0)
    program.audio_preferences['sound_pack'] = 'audiodisc'
    audio.refresh_preferences
    audio.update(snapshot, viewer: 0)
    assert(snapshot == original, 'Sound-pack change alters the game snapshot')
    assert(!program.sounds['audio_ball_left'].playing? && program.sounds['audio_ball_audiodisc_center'].playing?, 'Old loop survives the pack switch')
    created = program.created.dup
    100.times { audio.update(snapshot, viewer: 0); audio.refresh_preferences }
    assert(program.created == created, 'Steady flight/preferences allocate new audio handles')
    program.events.clear
    audio.goal(viewer: 0, winner: 0)
    names = program.events.map(&:first)
    assert(names.first == 'audio_ball_audiodisc_goal' && names.length == 2 && GameRoomRealtime::ScoreAnnouncements::GOAL_VOICES.include?(names.last), 'Audiodisc goal does not replace just the goal effect')
    assert(program.sounds['audio_ball_audiodisc_goal'].playing?, 'Audiodisc goal stops immediately')
    audio.point([2, 1], sets: [0, 0], set_finished: false, winner: 0, viewer: 0, finished: false, goal_at: program.now)
    program.audio_preferences['sound_pack'] = 'default'
    audio.refresh_preferences
    assert(program.sounds['audio_ball_audiodisc_goal'].playing?, 'Switching packs cuts an already agreed goal')
    [3.0, 3.5, 4.0].each { |at| program.now = at; audio.tick }
    assert(program.events.last(3).map(&:first) == %w[pong_scores pong_number2 pong_number1], 'Switching packs loses the score recording')
    audio.goal(viewer: 0, winner: 1)
    assert(GameRoomRealtime::ScoreAnnouncements::GOALS.include?(program.events[-2].first), 'Default pack does not restore the original goal effect')
    program.audio_preferences['sound_pack'] = 'audiodisc'
    audio.refresh_preferences
    assert(program.created == created, 'Switching back duplicates sound handles')
    audio.close
    assert(program.sounds.values.all? { |sound| sound.closes == 1 }, 'Closing switched packs leaks streams')
    assert(program.managed.sort_by(&:object_id) == program.released.sort_by(&:object_id), 'A cached pack was not released')
  end
end
