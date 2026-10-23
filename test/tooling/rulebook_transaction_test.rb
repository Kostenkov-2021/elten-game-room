require 'tmpdir'
require_relative '../support/assertions'
require_relative '../../tools/compile-rulebooks'
include GameRoomTest::Assertions

Dir.mktmpdir('rulebook-transaction-') do |root|
  input = File.join(root, 'tools/data/rulebooks')
  output = File.join(root, 'games/generated/rulebooks')
  FileUtils.mkdir_p([input, output])
  manifest = %w[first second third].to_h do |name|
    book = {source: "games/#{name}.rb", sections: [
      {id: 'goal', title: {en: 'Goal'}, paragraphs: [{en: "#{name}: Zażółć gęślą jaźń."}]}]}
    File.binwrite(File.join(input, "#{name}.json"), JSON.generate(book))
    ["#{name}.json", {source: "games/#{name}.rb", class: name.capitalize,
      kind: 'class', output: "games/generated/rulebooks/#{name}.rb"}]
  end
  File.binwrite(File.join(root, 'tools/rulebook_sources.json'), JSON.generate(manifest))
  paths = manifest.values.map { |entry| File.join(root, entry.fetch(:output)) }
  snapshot = -> { paths.to_h { |path| [path, File.exist?(path) ? File.binread(path) : nil] } }
  restore = lambda do
    File.binwrite(paths[0], '# original first')
    File.unlink(paths[1]) if File.exist?(paths[1])
    File.binwrite(paths[2], '# original third')
  end
  restore.call
  before = snapshot.call
  expected = manifest.values.map { |entry| entry.fetch(:output) }
  assert_equal(expected, GameRoomRulebookCompiler.run(root: root, check: true))
  assert_equal(before, snapshot.call, 'Check mode changed outputs')

  paths.drop(1).each do |fail_at|
    restore.call
    failed = false
    original_write, original_rename = File.method(:binwrite), File.method(:rename)
    File.define_singleton_method(:binwrite) do |path, *arguments|
      if path == fail_at && !failed
        failed = true
        raise IOError, 'Injected rulebook replacement failure'
      end
      original_write.call(path, *arguments)
    end
    File.define_singleton_method(:rename) do |source, target|
      if target == fail_at && !failed
        failed = true
        raise IOError, 'Injected rulebook replacement failure'
      end
      original_rename.call(source, target)
    end
    begin
      error = assert_raises(IOError) { GameRoomRulebookCompiler.run(root: root) }
      assert_equal('Injected rulebook replacement failure', error.message)
    ensure
      File.define_singleton_method(:binwrite, original_write)
      File.define_singleton_method(:rename, original_rename)
    end
    assert(failed, 'The actual compiler did not reach the injected write')
    assert_equal(before, snapshot.call, 'Failed generation left a mixed rulebook set')
    assert(Dir.glob(File.join(output, '.game-room-output-*')).empty?, 'Successful rollback left recovery files')
  end

  rendered = GameRoomRulebookCompiler.outputs(root)
  assert_equal(expected, GameRoomRulebookCompiler.run(root: root))
  rendered.each { |relative, bytes| assert_equal(bytes.b, File.binread(File.join(root, relative))) }
  assert(GameRoomRulebookCompiler.run(root: root, check: true).empty?, 'Successful generation is not reproducible')
end
puts 'PASS rulebook generator: exact old/absent-file rollback after second/third write failure, unchanged check mode and UTF-8 binary output'
