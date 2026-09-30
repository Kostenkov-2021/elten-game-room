require_relative "../../lib/game_random"

# Capture MRI's implementation before simulating ELTEN's no-argument override.
reference = Array.instance_method(:shuffle)
require_relative "../support/elten_array_shuffle"

[0, 1, 2, 7, 8, 28, 86, 100, 500].each do |length|
  [0, 1, 227, 2**128 - 1].each do |seed|
    values = Array.new(length) { |index| index }.freeze
    expected_rng, actual_rng = Random.new(seed), Random.new(seed)
    expected = reference.bind(values).call(random: expected_rng)
    actual = GameRoomRandom.shuffle(values, random: actual_rng)
    raise "Changed seeded order #{length}/#{seed}" unless actual == expected
    raise "Changed next random choice #{length}/#{seed}" unless 8.times.map { expected_rng.rand(1000) } == 8.times.map { actual_rng.rand(1000) }
    raise "Mutated input" unless values == Array.new(length) { |index| index } && !actual.equal?(values)
  end
end
duplicates = [nil, nil, 1, 1, :tile, :tile].freeze
result = GameRoomRandom.shuffle(duplicates, random: Random.new(227))
raise "Lost repeated values" unless result.tally == duplicates.tally
raise "All seeds gave the same order" if GameRoomRandom.shuffle((0...100).to_a, random: Random.new(1)) == GameRoomRandom.shuffle((0...100).to_a, random: Random.new(2))
puts "Portable seeded shuffle preserves MRI order, next RNG choices and all input values under ELTEN's API."
