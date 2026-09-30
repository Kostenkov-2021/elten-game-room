require_relative "../../support/binary_suite"

# Every original scenario retains its assertions and binary runtime boundary,
# with fresh fixture/global state and the common timeout/skip reporting.
BinaryTestSuite.run(%w[
  games/tysiac/two_player_ui_test.rb
  games/tysiac/two_player_bot_test.rb
  games/tysiac/two_player_save_test.rb
  games/tysiac/barrel_messages_test.rb
], mode: "dictionary", polish: [])
puts "PASS binary two-player Tysiac: model, bots, saved replay, UI, translations and barrel announcements"
