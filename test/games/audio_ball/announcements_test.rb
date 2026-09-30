require_relative "../../support/audio_ball_client"

[0, 1].each do |first|
  h = AudioBallHarness.new(server: first)
  messages = h.clients.to_h do |name, client|
    captured = []
    client.define_singleton_method(:speak) { |text, **options| captured << [text, options] }
    [name, captured]
  end
  h.advance(12)
  expected = "#{h.players[first]} serves."
  assert(messages.values.all? { |entries| entries == [[expected, {stop: false, break_sequence: false}]] }, 'random first server was not announced once without cutting speech')
  h.win_point('Alice'); h.advance_for(5.8)
  assert(messages.values.all? { |entries| entries.length == 1 }, 'second serve in the same block was announced again')
  h.win_point('Alice'); h.advance_for(5.8)
  expected = "#{h.players[1 - first]} serves."
  assert(messages.values.all? { |entries| entries.length == 2 && entries.last.first == expected }, 'server change was not announced after the point break')
  h.network.each_value { |channel| channel.epoch = 'same-service-reconnected' }
  h.advance_for(5.8)
  assert(messages.values.all? { |entries| entries.length == 2 }, 'reconnect repeated the current server announcement')
  h.close
end
h = AudioBallHarness.new
announcements = {}
h.audios.each do |name, audio|
  announcements[name] = []
  audio.define_singleton_method(:announce) { |text| announcements[name] << text }
end
h.clients.each_value do |client|
  client.define_singleton_method(:speak) { |*_args, **_options| raise 'Server bypassed the score-audio queue' }
end
h.advance(12)
assert(announcements.values.all? { |messages| messages == ['Alice serves.'] }, 'server did not enter the recorded-score announcement queue')
h.close
puts 'PASS Audio Ball server speech: both random starters, two-serve blocks, pause/reconnect deduplication and score-audio queue routing'
