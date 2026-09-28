require_relative "run-tests"

# A named selection only; execution, timeouts and reports belong to the shared runner.
args = ARGV.dup
historical = args.delete('--historical-audit')
tests = %w[
  test/quiz_data_cleanup_test.rb
  test/quiz_pack_builder_test.rb
  test/quiz_party_test.rb
  test/quiz_party_startup_test.rb
  test/quiz_party_review_regressions_test.rb
  test/quiz_party_translation_test.rb
  test/witcher_medium_split_test.rb
  test/game_content_test.rb
  test/hidden_submissions_storage_test.rb
  test/quiz_party_storage_test.rb
  test/categories_storage_test.rb
  test/game_option_form_test.rb
  test/surface_framework_test.rb
  test/packaged_rules_encoding_test.rb
  test/categories_test.rb
  test/tysiac_test.rb
  test/room_interface_test.rb
  test/game_rules_ui_test.rb
  test/game_rules_translation_test.rb
  test/game_messages_ui_test.rb
  test/game_sounds_test.rb
  test/observer_and_shortcut_regressions_test.rb
  test/uno_straights_test.rb
  test/native_live_sessions_store_test.rb
  test/live_sessions_resilience_test.rb
  test/live_sessions_multiplayer_test.rb
  test/transport_test.rb
  test/game_sync_test.rb
  test/connection_recovery_test.rb
  test/connection_recovery_ui_test.rb
  test/synchronization_regressions_test.rb
]
tests += %w[
  test/historical/quiz_factual_audit_test.rb
  test/historical/quiz_recovery_audit_test.rb
  test/historical/witcher_medium_audit_test.rb
] if historical
exit GameRoomTestRunner.cli(args, tests: tests, legacy_report: true)
