require_relative '../support/binary_suite'

# Each child has a fresh binary runtime and its own fixture globals.
BinaryTestSuite.run(%w[
  ui/score_announcement_order_test.rb
  ui/card_reshuffle_test.rb
  localization/card_announcements_encoding_test.rb
], mode: 'dictionary')
puts 'PASS binary card announcements: isolated score, reshuffle and dictionary scenarios'
