require_relative "../../support/binary_suite"

# Every original scenario retains its assertions and binary runtime boundary,
# with fresh fixture/global state and the common timeout/skip reporting.
BinaryTestSuite.run(%w[
  games/audio_ball/binary_boundary_test.rb
  games/audio_ball/client_test.rb
  games/audio_ball/warning_recovery_test.rb
  games/audio_ball/spectator_recovery_test.rb
  games/audio_ball/settings_client_test.rb
  games/audio_ball/difficulty_test.rb
  games/audio_ball/settings_test.rb
  games/audio_ball/point_audio_test.rb
  games/audio_ball/announcements_test.rb
  games/audio_ball/defense_input_test.rb
  games/audio_ball/lane_test.rb
  games/audio_ball/keyboard_test.rb
  games/audio_ball/fast_input_test.rb
  games/audio_ball/input_boundary_test.rb
  games/audio_ball/held_engine_test.rb
  games/audio_ball/flight_test.rb
  games/audio_ball/client_audio_tick_test.rb
  games/audio_ball/sound_pack_test.rb
  games/audio_ball/stop_cue_test.rb
], mode: "source", polish: [])
puts "PASS Audio Ball #{ARGV.first ? 'installer' : 'binary sources'}: actual runtime records, per-flight defense, seven-point matches, recovery and Pong score recordings"
