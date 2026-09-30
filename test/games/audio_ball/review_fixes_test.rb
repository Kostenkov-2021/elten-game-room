require_relative "../../support/audio_ball_client"

def audio_ball_agreed_miss(h)
  h.advance(16)
  server = h.players[h.replay.state[:server]]
  h.press(server, 'prepare', 'up') unless GameRoomParticipants.bot?(server)
  1_500.times do
    h.advance
    break if h.clients[h.instance_variable_get(:@owner)].context_data['audio_ball_point']
  end
  assert(h.clients[h.instance_variable_get(:@owner)].context_data['audio_ball_point'], 'no naturally agreed point')
  h.advance(8)
end

[
  {players: %w[Alice Bob], owner: 'Alice'},
  {players: %w[Bob Carol], owner: 'Alice'},
  {players: ['Alice', 'bot:20:1'], owner: 'Alice', server: 1},
  {players: ['bot:20:1', 'Bob'], owner: 'Alice', server: 0},
  {players: ['bot:20:1', 'bot:20:2'], owner: 'Alice', server: 0}
].each do |options|
  h = AudioBallHarness.new(**options)
  begin
    audio_ball_agreed_miss(h)
    assert(h.audios.values.all? { |audio| audio.calls.count { |call| call[0] == :goal } == 1 }, 'agreed goal waits for durable storage')
    assert(h.audios.values.none? { |audio| audio.calls.any? { |call| call[0] == :point } }, 'score presented before durable storage')
    assert(h.replay.state[:scores] == [0, 0], 'preview changed the durable score')
    h.advance_for(0.8)
    assert(h.audios.values.all? { |audio| audio.calls.count { |call| call[0] == :goal } == 1 }, 'preview repeats while storage is delayed')
    before = h.replay
    h.commit
    h.clients.each { |name, client| client.event(h.events.last, before, h.replay, name, h.repository) }
    assert(h.audios.values.all? { |audio| audio.calls.count { |call| call[0] == :point } == 1 }, 'durable point repeats')
    assert(h.audios.values.all? { |audio| audio.calls.find { |call| call[0] == :point }[2][:goal_at].is_a?(Numeric) }, 'durable presentation lost preview time')
    assert(h.audios.values.all? { |audio| audio.calls.count { |call| call[0] == :goal } == 1 }, 'durable storage played the goal twice')
  ensure
    h.close
  end
end
puts 'PASS agreed Audio Ball goal preview, durable-only score and deduplication for humans, bots and observing owners'

h = AudioBallHarness.new
begin
  h.advance(16)
  h.inject('Bob', 'Alice', {'action' => 'point', 'side' => 0, 'turn' => 0})
  h.inject('Alice', 'Bob', {'action' => 'point', 'side' => 0, 'turn' => 0})
  h.advance(8)
  assert(h.audios.values.none? { |audio| audio.calls.any? { |call| call[0] == :goal } }, 'unconfirmed or non-owner preview accepted')
  audio_ball_agreed_miss(h)
  h.advance_for(0.8)
  assert(h.surfaces.values.all? { |surface| surface.status == _('Waiting for the point to be saved.') }, 'pending point is described as a connection wait')
  preview_at = h.clients['Bob'].send(:point_state).goal_preview[:at]
  h.commit
  h.advance(8)
  assert(h.surfaces.values.all? { |surface| surface.status == _('Break between points.') }, 'normal break is described as waiting for players')
  h.advance_for(4.0)
  assert(h.clients.values.all?(&:paused), 'score/serve spacing was shortened')
  h.advance_for(0.9)
  assert(h.clients.values.none?(&:paused), 'the full point pause was restarted after a slow durable commit')
  assert(h.now - preview_at >= 5.7, 'point pause lost its minimum length')
  h.network['alice'].missing = ['bob']
  h.advance(8)
  assert(h.surfaces['Alice'].status == _('Waiting for players.'), 'real missing participant was masked as a point break')
ensure
  h.close
end
puts 'PASS point wait, point break and real connection wait are distinct; preview pause is reused'

class AudioBallIndependentAudioProgram
  def initialize(volume); @volume = volume; end
  def create_sound_from_asset(_name, **_options); nil; end
  def game_room_sound_enabled?(_name); true; end
  def game_room_sound_volume(_name); 1.0; end
  def pong_preferences; GameRoomPong::Preferences::DEFAULTS.merge('announcer_volume' => @volume); end
end

[0, 50, 100, 200].each do |volume|
  now, speech = 0.0, []
  audio = GameRoomAudioBall::Audio.new(AudioBallIndependentAudioProgram.new(volume),
    clock: -> { now }, speaker: ->(text) { speech << text }, speech_active: -> { false })
  begin
    audio.point([1, 0], sets: [0, 0], set_finished: false, winner: 0, viewer: 0, finished: false)
    now = 4.0
    audio.tick
    expected = GameRoomContent.utf8(_('Score: %{own} to %{opponent}.')) % {own: 1, opponent: 0}
    assert(audio.presents_point && speech == [expected], 'Pong personal volume changes Audio Ball presentation')
  ensure
    audio.close
  end
end
puts 'PASS Audio Ball point presentation is independent of personal Pong volume'
