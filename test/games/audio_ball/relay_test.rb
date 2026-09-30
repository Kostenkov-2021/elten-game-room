require_relative "../../support/audio_ball_relay"

h = AudioBallRelayHarness.new(options: {'sets_to_win' => 2})
h.wait_ready
assert(h.network.values.all? { |channel| channel.is_a?(GameRoomRealtime::EventChannel) }, 'native test replaced the real channel')
(h.points_to_win * 2).times do
  h.wait_ready
  h.win_point('Alice')
  assert(h.clients.values.all? { |client| client.instance_variable_get(:@replay).state == h.replay.state }, 'native clients disagree on durable score')
end
assert(h.replay.finished? && h.replay.state[:sets] == [2, 0], 'full native two-set match did not finish through actual fields')
assert(h.audios.values.all? { |audio| audio.calls.count([:set, 2]) == 1 }, 'native second-set speech was repeated or missing')
assert(h.rig.groups.length == 1, 'healthy native play unnecessarily reconnected')
h.close
assert(h.rig.endpoints.values.all?(&:closed?), 'native match leaked an endpoint')
puts "PASS Audio Ball: actual keyboard fields, real EventChannel and complete #{h.points_to_win * 2}-point/two-set match"

bot = GameRoomParticipants.bot_id(20, 1)
[
  {players: ['Alice', bot], owner: 'Alice', viewers: %w[Alice Watcher], server: 1},
  {players: [bot, 'Bob'], owner: 'Alice', viewers: %w[Alice Bob Watcher], server: 0}
].each do |options|
  h = AudioBallRelayHarness.new(**options)
  80_000.times do
    h.autoplay_step
    break if h.replay.finished?
  end
  assert(h.replay.finished?, 'native bot match did not finish through legal input and scoring')
  assert(h.replay.state[:sets].max == 1 && h.replay.state[:last_point][:scores].max >= h.points_to_win, 'native bot match did not obey set scoring')
  puts "PASS Audio Ball native bot match: owner=#{options[:owner]}, players=#{options[:players].join('/')}, points=#{h.replay.state[:rally]}, sets=#{h.replay.state[:sets].inspect}"
  h.close
  assert(h.rig.endpoints.values.all?(&:closed?), 'native bot match leaked an endpoint')
end
