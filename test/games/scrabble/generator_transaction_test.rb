require 'digest'
require 'fileutils'
require 'open3'
require 'rbconfig'
require_relative '../../support/temporary_directory'
require_relative '../../support/assertions'
require_relative '../../../tools/build-scrabble-dictionaries'
include GameRoomTest::Assertions

GameRoomTest::TemporaryDirectory.create('scrabble-generator-') do |root|
  %w[inputs content lib].each { |path| FileUtils.mkdir_p(File.join(root, path)) }
  repository = File.expand_path('../../..', __dir__)
  FileUtils.cp(File.join(repository, 'lib/game_content.rb'), File.join(root, 'lib/game_content.rb'))
  inputs, content = %w[inputs content].map { |name| File.join(root, name) }
  sources = [['en', 'English fixture', 'cat\ndog\n'], ['pl-PL', 'Polish fixture', "kot\npies\n"]].map do |language, title, text|
    text = text.gsub('\\n', "\n")
    filename = language + '.txt'
    File.binwrite(File.join(inputs, filename), text)
    {language: language, input: filename, source: 'owned test fixture', title: title, author: 'Test', license: 'CC0-1.0',
      alphabet: /\A[a-z]{2,15}\z/, sha: Digest::SHA256.hexdigest(text)}
  end
  build = -> { GameRoomScrabbleDictionaries.build(source_dir: inputs, destination: content, sources: sources) }
  snapshot = -> { Dir.glob('*.rb', base: content).to_h { |name| [name, File.binread(File.join(content, name))] } }

  # The fixture has its own real checksum; production's pinned source is not bypassed.
  original = File.binread(File.join(inputs, 'pl-PL.txt'))
  File.binwrite(File.join(inputs, 'pl-PL.txt'), "\xFF".b)
  invalid_sources = [sources.first, sources.last.reject { |key, _| key == :sha }]
  error = assert_raises(RuntimeError) do
    GameRoomScrabbleDictionaries.build(source_dir: inputs, destination: content, sources: invalid_sources)
  end
  assert(error.message.include?('Source is not UTF-8'), 'Invalid PL source failed at another boundary')
  assert(snapshot.call.empty?, 'EN was published before PL validation')
  File.binwrite(File.join(inputs, 'pl-PL.txt'), original)
  build.call
  before = snapshot.call
  changed = original + "las\n"
  File.binwrite(File.join(inputs, 'pl-PL.txt'), changed)
  sources[-1] = sources.last.merge(sha: Digest::SHA256.hexdigest(changed))

  original_rename = File.method(:rename)
  failed = false
  File.define_singleton_method(:rename) do |from, to|
    if File.basename(to) == 'scrabble_words_pl.rb' && !failed
      failed = true
      raise IOError, 'Injected final Scrabble wrapper failure'
    end
    original_rename.call(from, to)
  end
  begin
    assert_raises(IOError) { build.call }
  ensure
    File.define_singleton_method(:rename, original_rename)
  end
  assert(failed, 'Final output replacement failure was not reached')
  assert_equal(before, snapshot.call, 'Replacement failure changed part of the bilingual output')
  assert(Dir.glob(File.join(content, '.game-room-output-*')).empty?, 'Rollback left temporary files')

  # Load both wrappers with the real Pack validation in a fresh process.
  code = "require #{File.join(root, 'lib/game_content.rb').inspect}; " +
    %w[en pl-PL].map { |language| "GameRoomContent.registry.register_language(GameRoomContent::LanguageProfile.new(id: #{language.inspect}, label: 'Fixture', alphabet: ['a'], normalizer: ->(text) { text.downcase }));" }.join +
    %w[en pl].map { |language| "require #{File.join(content, "scrabble_words_#{language}.rb").inspect};" }.join +
    "GameRoomContent.registry.packs.each { |pack| raise 'Wrong dictionary count' unless pack.data.fetch('count') == 2 }"
  output, error, status = Open3.capture3(RbConfig.ruby, '-e', code)
  assert(status.success?, "Actual dictionary loader failed: #{output} #{error}")
end
puts 'PASS Scrabble generator: validate both inputs before outputs, exact four-file rollback and actual loaders'
