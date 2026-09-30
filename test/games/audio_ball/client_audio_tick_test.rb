require_relative "../../support/audio_ball_client"

clock = -> { 123.0 }
audio_class = GameRoomAudioBall::Audio
original_new = audio_class.method(:new)
received_clock = nil
begin
  audio_class.define_singleton_method(:new) do |_program, **options|
    received_clock = options[:clock]
    AudioBallTestAudio.new
  end
  client = GameRoomAudioBall::Client.new(Program.new, GameRoomGames::AudioBall.new, clock: clock)
  assert(received_clock.equal?(clock), 'Client did not give its monotonic clock to the default Audio')
  client.close
ensure
  audio_class.define_singleton_method(:new, original_new)
end
puts 'PASS Audio Ball client audio: default Audio receives the injected client clock'

h = AudioBallHarness.new
h.advance(12)
h.win_point('Alice')
point_at = h.now
h.advance_for(5.68)
assert(h.clients.values.all?(&:paused), 'ordinary point resumed before the 3-second score and 2.7-second serve pause')
h.advance_for(0.12)
assert(h.now - point_at >= 5.7 && h.clients.values.none?(&:paused), 'ordinary point did not resume after 5.7 seconds')
h.close
puts 'PASS Audio Ball client audio: ordinary points wait 5.7 elapsed seconds without a speech barrier'

class AudioBallPendingRecording < AudioBallTestAudio
  attr_accessor :presents_point
  attr_reader :ticks
  def initialize(clock:)
    super()
    @clock, @ticks, @presents_point = clock, 0, true
  end
  def point(scores, **options)
    super
    @pending = [@clock.call + 3.0, scores, options]
  end
  def tick
    @ticks += 1
    return unless @pending && @clock.call >= @pending.first
    @calls << [:recorded_score, @pending[1], @pending[2]]
    @pending = nil
  end
  def close
    @pending = nil
    super
  end
end

h = AudioBallHarness.new(audio_factory: ->(**options) { AudioBallPendingRecording.new(**options) })
h.advance(12)
before = h.replay
h.win_point('Alice')
h.clients.each do |name, client|
  client.event(h.events.last, before, h.replay, name, h.repository)
  client.detach_view
end
h.now += 3.01
h.clients.each_value(&:tick)
assert(h.audios.values.all? { |audio| audio.calls.count { |call| call[0] == :recorded_score } == 1 },
  'a detached view stopped the pending score recording from advancing through Client.tick')
assert(h.audios.values.all? { |audio| audio.calls.count { |call| call[0] == :point } == 1 },
  'the same durable point was scheduled twice')
h.clients.each do |name, client|
  [false, true].each do |enabled|
    h.audios[name].presents_point = enabled
    assert(client.presents_game_event?(h.events.last) == enabled, 'muted point audio suppressed the normal event text fallback')
    assert(!client.presents_game_event?({'action' => 'audio_ball_start'}), 'audio claimed an unrelated game event')
  end
end
h.close
puts 'PASS Audio Ball client audio: detached view continues recordings and duplicate durable events stay suppressed'

h = AudioBallHarness.new(audio_factory: ->(**options) { AudioBallPendingRecording.new(**options) })
h.advance(12)
h.points_to_win.times do |point|
  h.win_point('Alice')
  h.advance_for(5.8) unless point == h.points_to_win - 1
end
assert(h.replay.finished?, 'recording fixture did not finish a real match')
assert(h.audios.values.all? { |audio| audio.calls.count { |call| call[0] == :recorded_score } == h.points_to_win - 1 },
  'final score recording did not remain pending when the match finished')
h.now += 3.01
3.times { h.clients.each_value(&:tick) }
assert(h.audios.values.all? { |audio| audio.calls.count { |call| call[0] == :recorded_score } == h.points_to_win },
  'finished replay prevented the last score recording from advancing through Client.tick')
assert(h.audios.values.all? { |audio| audio.calls.count { |call| call[0] == :point } == h.points_to_win },
  'finished ticks duplicated a point event')
h.clients.each do |name, client|
  [false, true].each do |enabled|
    h.audios[name].presents_point = enabled
    assert(client.presents_game_result?(h.replay) == enabled, 'muted final point audio suppressed the normal result text fallback')
  end
end
h.close
ticks = h.audios.transform_values(&:ticks)
h.clients.each_value(&:tick)
assert(h.audios.all? { |name, audio| audio.ticks == ticks[name] }, 'closed client kept ticking audio')
puts 'PASS Audio Ball client audio: final score continues after replay completion and stops on close'
