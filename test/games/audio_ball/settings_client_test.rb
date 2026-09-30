require_relative "../../support/audio_ball_client"

h = AudioBallHarness.new
h.advance(12)
client = h.clients.fetch('Alice')
assert(client.respond_to?(:show_settings), 'Audio Ball has no active-match settings entry point')
program = client.instance_variable_get(:@program)
calls = 0
program.define_singleton_method(:show_audio_ball_settings) do |tick:, clock:|
  calls += 1
  assert(clock.call == h.now, 'settings use a different match clock')
  client.show_settings
  h.surfaces['Alice'].push('prepare', 'up')
  h.now += 0.02
  tick.call
  assert(client.engine.turn == 0, 'settings dialog input leaked into the match')
  {'side' => 'left'}
end
client.show_settings
assert(calls == 1 && !client.instance_variable_get(:@settings_open), 'settings reentered or kept input blocked after closing')
h.press('Alice', 'prepare', 'up')
assert(client.engine.phase == :flying, 'fresh gameplay did not resume after closing settings')
program.define_singleton_method(:show_audio_ball_settings) { |**_options| raise 'injected settings error' }
begin
  client.show_settings
rescue RuntimeError => error
  raise unless error.message == 'injected settings error'
end
assert(!client.instance_variable_get(:@settings_open), 'failed settings window permanently blocked the playfield')
h.close
h = AudioBallHarness.new(server: 1)
h.advance(12)
client = h.clients.fetch('Alice')
client.instance_variable_get(:@program).define_singleton_method(:show_audio_ball_settings) do |**_options|
  assert(!h.surfaces['Alice'].on_audio_ball_command.call('hurry'), 'modal settings issued a gameplay warning')
end
client.show_settings
assert(client.engine.warning == nil, 'modal settings altered the opponent deadline')
h.close
puts 'PASS Audio Ball active settings: shared clock/tick, no gameplay keys or warnings, reentry guard and cleanup'
