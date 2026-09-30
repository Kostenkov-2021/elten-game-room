require_relative '../../support/assertions'
require_relative '../../../tools/generate-krowa-nouns'
include GameRoomTest::Assertions

result = GameRoomNounGenerator.run(check: true)
assert_equal(98_187, result[:entries])
source = File.read(File.join(GameRoomNounGenerator::ROOT, 'tools/data/krowa_nouns.txt'), encoding: 'UTF-8')
lines = source.lines
assert_equal('5e9e97a7681e662e97527a794846f965a0b789e1f47b3c06c5fc8404490d0389', Digest::SHA256.hexdigest(lines.first(98_178).join))
additions = %w[łam zacios zaciosy prosię silnia silnie afro szmat ksero]
assert_equal(additions, lines.drop(98_178).map(&:chomp))
words = lines.map(&:chomp)
additions.each { |word| assert_equal(1, words.count(word)) }
assert_equal(GameRoomNounGenerator.render("word\nwords\n"), GameRoomNounGenerator.render("word\nwords\n"))
assert_raises(RuntimeError) { GameRoomNounGenerator.render("KROWA_NOUNS\n") }
[" KROWA_NOUNS\n", "\tKROWA_NOUNS\n", " \t\n"].each do |text|
  assert_raises(RuntimeError) { GameRoomNounGenerator.render(text) }
end

puts 'PASS Krowa noun source provenance, stable generation and heredoc validation'
