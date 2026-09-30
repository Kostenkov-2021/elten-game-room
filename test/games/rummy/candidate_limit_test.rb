require "digest"
require_relative "../../../lib/rummy_planner"

def assert(condition, message)
  raise message unless condition
end

module RummyCandidateValidationCount
  attr_accessor :validation_count

  def validate(*args, **options)
    self.validation_count = validation_count.to_i + 1
    super
  end
end
GameRoomRummyRules.singleton_class.prepend(RummyCandidateValidationCount)

# Full ordered candidate representations captured from the pre-change planner
# on 25 September, not a new reference generated from the optimized code.
historical = {
  14 => [77, 308, "c1ea472e4946758cd0ced35ad06394d0e9e19fc4af784bb8901c0ca299f7df23"],
  40 => [248, 992, "595a43f51de7d370e578bfd29fe91afcf28d63e20ea09944a8ce580e61c04eea"],
  80 => [420, 874, "a2eb46a273b75144a84a89f9b6a021241c0e4b50e9bcf633789fbabe59a79969"],
  216 => [420, 420, "67bea52e821553a73aa0799baf60a820b127d1a15f7ddecfbee0877bc96e8307"]
}
deck = GameRoomRummyRules.deck(4)
historical.each do |size, (count, validations, digest)|
  [false, true].each do |identities|
    hand = deck.first(size)
    original = hand.dup
    GameRoomRummyRules.validation_count = 0
    candidates = GameRoomRummyPlanner.candidates(hand, identities: identities)
    assert(candidates.length == count, "candidate count changed for #{size}/#{identities}")
    assert(GameRoomRummyRules.validation_count == validations, "validation did not stop at cap for #{size}/#{identities}")
    assert(Digest::SHA256.hexdigest(Marshal.dump(candidates)) == digest, "candidate order/content changed for #{size}/#{identities}")
    assert(hand == original, "candidate generation mutated input")
  end
end

# The large hands above are synthetic load cases, not claims about reachable
# normal play. This small hand checks real physical duplicates and jokers.
hand = %w[AC0 AC1 AC2 AC3 AD0 AH0 AS0 2C0 3C0 X00 X01]
[false, true].each do |identities|
  candidates = GameRoomRummyPlanner.candidates(hand, identities: identities)
  repeated = GameRoomRummyPlanner.candidates(hand + %w[AC0 X00], identities: identities)
  assert(candidates == repeated, "duplicate physical IDs changed candidates")
  assert(candidates.any? { |meld| meld[:cards].include?("X00") }, "joker candidates disappeared")
  assert(candidates.any? { |meld| meld[:type] == :identity } == identities, "identity option changed")
  assert(candidates.all? { |meld| meld[:cards].uniq == meld[:cards] }, "a physical card occurs twice in a meld")
  assert(candidates.all? { |meld| GameRoomRummyRules.validate(meld[:cards], identities: identities) == meld }, "invalid candidate")
end

puts "PASS Rummy candidate limit: eight historical ordered fingerprints, exact validation counts, duplicates, jokers and identities"
