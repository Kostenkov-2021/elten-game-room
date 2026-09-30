require_relative '../../lib/game_room_plural_rule'
require_relative '../support/assertions'
Object.include(GameRoomTest::Assertions)

{ '(n-5)/2' => [-2, -2, -1, -1, 0, 0, 0, 1],
  '(n-5)%2' => [-1, 0, -1, 0, -1, 0, 1, 0],
  '(n-5)/-2' => [2, 2, 1, 1, 0, 0, 0, -1],
  '(n-5)%-2' => [-1, 0, -1, 0, -1, 0, 1, 0]
}.each do |source, expected|
  rule = GameRoomLocalization::PluralRule.new(source)
  assert_equal(expected, 8.times.map { |n| rule.index(n) }, source)
end
%w[n/0 n%0].each { |source| assert(GameRoomLocalization::PluralRule.new(source).index(1).nil?) }
{ 'n==1 ? 0 : 1/0' => 0, 'n==1 || 1/0' => 1, 'n!=1 && 1/0' => 0 }.each do |source, expected|
  assert_equal(expected, GameRoomLocalization::PluralRule.new(source).index(1), 'Lost short circuit')
end
puts 'PASS gettext integer division/remainder and short circuit with negative intermediate values'
