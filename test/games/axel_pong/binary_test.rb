require_relative "../../support/binary_suite"

# Every original scenario retains its assertions and binary runtime boundary,
# with fresh fixture/global state and the common timeout/skip reporting.
BinaryTestSuite.run(%w[
  games/axel_pong/engine_test.rb
  realtime/realtime_protocol_test.rb
  games/axel_pong/integration_test.rb
  games/axel_pong/rally_sync_test.rb
  games/axel_pong/serve_input_test.rb
  games/axel_pong/audio_feedback_test.rb
  games/axel_pong/point_audio_test.rb
  games/axel_pong/reference_test.rb
  games/axel_pong/audio_reference_test.rb
  games/axel_pong/hurry_test.rb
  games/axel_pong/peer_events_test.rb
  games/axel_pong/frame_timing_test.rb
  games/axel_pong/mouse_client_test.rb
  games/axel_pong/deep_parity_test.rb
  games/axel_pong/parity_fixes_test.rb
  games/axel_pong/source_physics_test.rb
  games/axel_pong/source_audio_test.rb
  games/axel_pong/source_client_test.rb
  games/axel_pong/settings_test.rb
  realtime/realtime_recovery_test.rb
  realtime/realtime_delivery_test.rb
  games/axel_pong/connection_recovery_test.rb
  games/axel_pong/network_wait_test.rb
  games/axel_pong/goal_latency_test.rb
  games/axel_pong/rematch_test.rb
  games/axel_pong/history_feedback_test.rb
  games/axel_pong/spectator_test.rb
], mode: "pong", polish: [])
puts 'PASS binary Pong: engine, protocol, channel, audio, clients, durable points and PL/EN UI'
