require_relative "../realtime/score_announcements"
require_relative "sound_pack"
require_relative '../game_sound_output'

module GameRoomAudioBall
  class PointAudio
    include GameRoomRealtime::ScoreAnnouncements
    WRONG_TURN = 'audio_ball_wrong_turn'.freeze

    def initialize(program, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, rng: Random.new,
      speaker: nil, speech_active: nil)
      @program, @clock, @rng = program, clock, rng
      @sounds, @frequencies, @levels = {}, {}, {}
      initialize_score_announcements(speaker: speaker, speech_active: speech_active)
    end

    def load
      return if @loaded
      ANNOUNCEMENTS.each { |name| load_sound(name, name) }
      load_sound(WRONG_TURN, WRONG_TURN)
      refresh_preferences
      @loaded = true
    end

    def refresh_preferences
      asset = SoundPack.asset('goal', @program)
      return if defined?(@goal_asset) && @goal_asset == asset
      @goal_asset = asset
      load_sound(@goal_asset, @goal_asset) if @goal_asset && !@sounds[@goal_asset]
    end

    def goal(viewer:, winner: nil, reason: nil)
      clear_announcements
      return unless presentation_enabled?
      @sounds.each { |name, sound| sound.pause unless ANNOUNCEMENTS.include?(name) }
      if reason == 'wrong_turn'
        play_announcement(WRONG_TURN)
      else
        play_goal_recordings(@goal_asset && @sounds[@goal_asset] ? @goal_asset : nil)
      end
    end

    def announce(text)
      at = [@clock.call, @score_queue.last ? @score_queue.last[0] : 0].max
      @score_queue << [at, {speech: text}]
      tick
    end

    def presentation_enabled?
      gain('pong_goal') > 0 && personal_gain('pong_scores') > 0
    end

    def cancel
      clear_announcements
    end

    def tick
      now = @clock.call
      return clear_announcements unless presentation_enabled?
      retire_announcements(now)
      @levels.each { |name, level| apply_mix(name, level) if @sounds[name]&.playing? }
      advance_score_queue(now)
    end

    def close
      clear_announcements
      @sounds.each_value do |sound|
        @program.release(sound) if @program.respond_to?(:release)
        sound.close
      end
      @sounds.clear
      @loaded = false
    end

    private

    def load_sound(asset, key)
      sound = @program.create_sound_from_asset(asset, loop: false)
      return unless sound
      @program.manage(sound) if @program.respond_to?(:manage)
      @sounds[key] = sound
      @frequencies[key] = sound.frequency
    end

    def play_sound(name, level: 1.0, silent: false)
      sound = @sounds[name]
      return unless sound && gain(name) > 0
      GameRoomSoundOutput.apply(@program, sound, 0.0, restart: true, silent: silent)
      @levels[name] = level
      apply_mix(name, level)
      sound.frequency = @frequencies[name]
      sound.position = 0
      sound.play
      sound
    end

    def apply_mix(name, level)
      @sounds[name].pan = 0
      GameRoomSoundOutput.apply(@program, @sounds[name], (level * gain(name)).clamp(0.0, 1.0))
    end

    # Audio Ball has no personal score slider; only shared Game Room volume.
    def personal_gain(_name)
      1.0
    end

    def gain(asset)
      return 0.0 if @program.respond_to?(:game_room_sound_enabled?, true) && !@program.send(:game_room_sound_enabled?, asset)
      @program.respond_to?(:game_room_sound_volume, true) ? @program.send(:game_room_sound_volume, asset) : 1.0
    end
  end
end
