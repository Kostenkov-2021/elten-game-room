require_relative "../../support/binary_rules_load"
ui_method = FakeControl.instance_method(:update)
BinaryRulesLoad.load(File.join(BinaryRulesLoad::ROOT, 'test/support/ui.rb'))
raise 'Binary loader reloaded an already required test helper' unless FakeControl.instance_method(:update) == ui_method
require_relative "../../support/audio_ball_client"

%w[games/audio_ball.rb lib/audio_ball/engine.rb lib/audio_ball/bot.rb lib/audio_ball/audio.rb lib/audio_ball/point_audio.rb lib/audio_ball/client.rb lib/audio_ball/keyboard.rb lib/audio_ball/defense_input.rb lib/audio_ball/preferences.rb lib/audio_ball/sound_pack.rb lib/audio_ball/settings.rb lib/game_surfaces/audio_ball_surface.rb].each do |name|
  path = File.join(BinaryRulesLoad::ROOT, name)
  raise "Audio Ball runtime bypassed binary loading: #{name}" unless BinaryRulesLoad.instance_variable_get(:@loaded)[path]
end
puts 'PASS Audio Ball binary runtime and fixture boundary'
