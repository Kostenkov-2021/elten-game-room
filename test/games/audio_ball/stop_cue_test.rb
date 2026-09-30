require_relative "../../support/audio_ball_client"

class AudioBallCueProbe < AudioBallTestAudio
  def stop_ball(side, viewer:); @calls << [:stop_ball, side, viewer]; end
  def refresh_preferences; @calls << [:refresh_preferences]; end
end

%w[Alice Bob].each do |server|
  side = server == 'Alice' ? 0 : 1
  receiver = side == 0 ? 'Bob' : 'Alice'
  h = AudioBallHarness.new(server: side, audio_factory: ->(**_) { AudioBallCueProbe.new })
  h.advance(12)
  h.press(server, 'prepare', 'up')
  h.press(receiver, 'left')
  assert(h.audios.values.all? { |audio| audio.calls.none? { |call| call.first == :stop_ball } }, 'Arming a wrong defence plays the catch cue')
  h.press(receiver, 'up')
  h.advance_for(1.6)
  assert(h.clients.values.all? { |client| client.engine.holder == 1 - side && client.engine.phase == :waiting }, 'Scenario did not reach a successful defence')
  h.audios.each do |name, audio|
    viewer = h.players.index(name) || 0
    assert(audio.calls.select { |call| call.first == :stop_ball } == [[:stop_ball, 1 - side, viewer]],
      "Local/remote/observer stop cue missing or duplicated for #{name}")
  end
  channel = h.network[receiver.downcase]
  packet = channel.event_sent.find { |data| JSON.parse(data).fetch('d')['action'] == 'defend' }
  assert(packet, 'The defence did not follow the real accepted event path')
  3.times { channel.deliver_event(packet) }
  h.advance(12)
  assert(h.audios.values.all? { |audio| audio.calls.count { |call| call.first == :stop_ball } == 1 }, 'Duplicate packets replay the catch cue')
  h.add_client('Late observer')
  h.advance(12)
  channel.deliver_event(packet)
  h.advance(3)
  assert(h.audios['Late observer'].calls.none? { |call| call.first == :stop_ball }, 'A late observer replayed a historical catch from the initial snapshot')
  client = h.clients[receiver]
  program = client.instance_variable_get(:@program)
  program.define_singleton_method(:show_audio_ball_settings) do |**_|
    client.show_settings
    nil
  end
  client.show_settings
  assert(h.audios[receiver].calls.count { |call| call.first == :refresh_preferences } == 1, 'Settings do not refresh audio exactly once after closing')
  program.define_singleton_method(:show_audio_ball_settings) { |**_| raise IOError, 'simulated settings failure' }
  begin
    client.show_settings
  rescue IOError
  end
  assert(!client.instance_variable_get(:@settings_open) && h.audios[receiver].calls.count { |call| call.first == :refresh_preferences } == 2,
    'Failed settings leave audio/input in an inconsistent state')
  h.close
end
puts 'PASS Audio Ball stop cue: accepted defence on both sides, sender/receiver/observer, packet deduplication and settings refresh'
