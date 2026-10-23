require 'digest'
require 'fileutils'
require 'open3'
require 'rbconfig'
require_relative '../../support/temporary_directory'
require_relative '../../support/assertions'
require_relative '../../../tools/support/quiz_pack_writer'
include GameRoomTest::Assertions

# Fail the wrapper publication, not data validation or the runtime loader.
File.singleton_class.prepend(Module.new do
  def write(path, ...)
    probe = Thread.current[:quiz_publication_failure]
    if probe && path == probe[:path] && !probe[:hit]
      probe[:hit] = true
      raise IOError, 'Injected quiz wrapper failure'
    end
    super
  end
  def rename(source, target)
    probe = Thread.current[:quiz_publication_failure]
    if probe && target == probe[:path] && !probe[:hit]
      probe[:hit] = true
      raise IOError, 'Injected quiz wrapper failure'
    end
    super
  end
end)

GameRoomTest::TemporaryDirectory.create('quiz-publication-') do |root|
  %w[lib content].each { |path| FileUtils.mkdir_p(File.join(root, path)) }
  repository = File.expand_path('../../..', __dir__)
  FileUtils.cp(File.join(repository, 'lib/game_content.rb'), File.join(root, 'lib/game_content.rb'))
  # Preserve each caller's original Windows newline mode, including Unicode.
  text = "First line.\nŻółw — second line.\n"
  reference = File.join(root, 'reference.txt')
  staged = File.join(root, 'staged.txt')
  File.write(reference, text, encoding: 'UTF-8')
  GameRoomToolOutputs.commit({staged => text}, label: 'Text fixture', binary: false)
  assert_equal(File.binread(reference), File.binread(staged), 'Text staging changed native File.write bytes')
  GameRoomToolOutputs.commit({staged => text}, label: 'Binary fixture')
  assert_equal(text.b, File.binread(staged), 'Binary staging changed bytes')
  metadata = {id: 'quiz.output.en', set_id: 'quiz.output', kind: 'quiz', language_id: 'en',
    version: 1, title: 'Publication fixture', game_ids: ['quiz']}
  question = ->(prompt) { [{id: 'one', prompt: prompt, correct: 'Right', wrong: %w[First Second Third]}] }
  existing = File.join(root, 'content/existing.rb')
  QuizPackWriter.write(existing, metadata, question.call('Original question?'))

  [existing, File.join(root, 'content/new.rb')].each do |path|
    data_path = path.sub(/\.rb\z/, '_data.rb')
    files = [path, data_path]
    snapshot = -> { files.to_h { |file| [file, File.exist?(file) ? File.binread(file) : nil] } }
    before = snapshot.call
    probe = {path: path, hit: false}
    begin
      Thread.current[:quiz_publication_failure] = probe
      assert_raises(IOError) { QuizPackWriter.write(path, metadata, question.call('Changed question?')) }
    ensure
      Thread.current[:quiz_publication_failure] = nil
    end
    assert(probe[:hit], 'Wrapper publication failure was not reached')
    assert_equal(before, snapshot.call, 'Failure left only part of the generated pack')
    assert(Dir.glob(File.join(root, 'content/.game-room-output-*')).empty?, 'Rollback left temporary files')
  end

  # A fresh real loader still checks and loads the previously valid pack.
  load_pack = lambda do |expected|
    code = "require #{File.join(root, 'lib/game_content.rb').inspect}; " \
      "GameRoomContent.registry.register_language(GameRoomContent::LanguageProfile.new(id: 'en', label: 'English', alphabet: ['a'], normalizer: ->(text) { text.downcase })); " \
      "require #{existing.inspect}; raise 'Wrong data' unless GameRoomContent.registry.pack('quiz.output.en').data.fetch('questions').first.fetch('prompt') == #{expected.inspect}"
    output, error, status = Open3.capture3(RbConfig.ruby, '-e', code)
    assert(status.success?, "Actual pack load failed: #{output} #{error}")
  end
  load_pack.call('Original question?')
  QuizPackWriter.write(existing, metadata, question.call('Changed question?'))
  load_pack.call('Changed question?')
end
puts 'PASS quiz output set: existing and new destinations, failed wrapper replacement, exact rollback and actual loader'
