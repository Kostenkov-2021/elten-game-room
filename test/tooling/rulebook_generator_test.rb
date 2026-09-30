require 'tmpdir'
require_relative "../support/assertions"
require_relative "../../tools/compile-rulebooks"
require_relative "../../tools/support/translation_extractor"
include GameRoomTest::Assertions

compiler = GameRoomRulebookCompiler
assert(compiler.run(check: true).empty?, 'generated rulebooks are stale')
assert(GameRoomTranslationExtractor.source_files(compiler::ROOT).include?('games/generated/rulebooks/uno.rb'), 'generated rules excluded from gettext')
Dir.mktmpdir('rulebook-contract') do |root|
  %w[tools/data/rulebooks tools games].each { |path| FileUtils.mkdir_p(File.join(root, path)) }
  book = {source: 'games/example.rb', sections: [{id: 'goal', title: {en: 'Goal'}, paragraphs: [{en: 'First sentence.'}]}]}
  manifest = {'example.json' => {class: 'Example', kind: 'class', source: 'games/example.rb', output: 'games/generated/rulebooks/example.rb'}}
  File.write(File.join(root, 'tools/data/rulebooks/example.json'), JSON.generate(book))
  File.write(File.join(root, 'tools/rulebook_sources.json'), JSON.generate(manifest))
  maintained = File.join(root, 'games/example.rb')
  File.binwrite(maintained, '# maintained model')
  expected = ['games/generated/rulebooks/example.rb']
  assert_equal(expected, compiler.run(root: root, check: true))
  assert(!File.exist?(File.join(root, expected.first)), 'check mode wrote an output')
  assert_equal(expected, compiler.run(root: root))
  bytes = File.binread(File.join(root, expected.first))
  assert(compiler.run(root: root).empty?, 'second generation was not reproducible')
  File.binwrite(File.join(root, expected.first), 'stale')
  assert_equal(expected, compiler.run(root: root, check: true))
  assert_equal('stale', File.binread(File.join(root, expected.first)), 'check repaired instead of failing')
  compiler.run(root: root)
  assert_equal(bytes, File.binread(File.join(root, expected.first)))
  assert_equal('# maintained model', File.binread(maintained), 'compiler patched maintained code')
  duplicate = book.merge(source: 'games/other.rb')
  File.write(File.join(root, 'tools/data/rulebooks/other.json'), JSON.generate(duplicate))
  manifest['other.json'] = manifest.fetch('example.json').merge(class: 'Other', source: 'games/other.rb')
  File.write(File.join(root, 'tools/rulebook_sources.json'), JSON.generate(manifest))
  [true, false].each do |check|
    assert_raises(ArgumentError) { compiler.run(root: root, check: check) }
    assert_equal(bytes, File.binread(File.join(root, expected.first)), 'conflicting outputs allowed a partial generation')
  end
end
puts 'PASS rulebooks: read-only check, deterministic output, gettext and model ownership'
