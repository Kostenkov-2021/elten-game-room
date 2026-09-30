require_relative "../support/binary_suite"

# Every original scenario retains its assertions and binary runtime boundary,
# with fresh fixture/global state and the common timeout/skip reporting.
BinaryTestSuite.run(%w[
  room/widget_feedback_binary_test.rb
  room/widget_and_games_feedback_test.rb
  games/krowa/reroll_test.rb
], mode: "dictionary", polish: ["room/widget_feedback_binary_test.rb"])
puts "PASS binary feedback: widget creation/presets, privacy, new game controls and Krowa reroll"
