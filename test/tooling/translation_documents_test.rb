require 'tmpdir'
require 'fileutils'
require_relative '../../tools/support/translation_documents'
require_relative '../support/assertions'
include GameRoomTest::Assertions

def file_snapshot(root)
  Dir.glob('**/*', base: root).select { |name| File.file?(File.join(root, name)) }
    .to_h { |name| [name, File.binread(File.join(root, name))] }
end

Dir.mktmpdir('game-room-translated-docs-') do |root|
  %w[locale tools/data/rulebooks].each { |directory| FileUtils.mkdir_p(File.join(root, directory)) }
  book_path = File.join(root, 'tools/data/rulebooks/example.json')
  book = { 'source' => 'games/example.rb', 'sections' => [{ 'id' => 'rules',
    'title' => { 'en' => 'Rules', 'pl' => 'POISON' },
    'paragraphs' => [{ 'en' => 'Play.', 'pl' => 'POISON' }, { 'en' => '%{count} question', 'pl' => 'POISON' }] }] }
  File.write(book_path, JSON.generate(book))
  messages = { 'Rules' => 'Zasady', 'Play.' => 'Graj.',
    "%{count} question\0%{count} questions" => "%{count} pytanie\0%{count} pytania\0%{count} pytań" }
  result = GameRoomTranslationDocuments.sync(root, messages)
  assert_equal([book_path], result)
  updated = JSON.parse(File.read(book_path))
  assert_equal({ 'en' => 'Rules', 'pl' => 'Zasady' }, updated['sections'][0]['title'])
  assert_equal(['Graj.', '%{count} pytanie'], updated['sections'][0]['paragraphs'].map { |pair| pair['pl'] })
  assert(Dir.empty?(File.join(root, 'locale')), 'Documentation sync created a catalog')
  snapshot = file_snapshot(root)
  assert(GameRoomTranslationDocuments.sync(root, messages).empty?, 'Document generation is not idempotent')
  GameRoomTranslationDocuments.sync(root, messages, check: true)
  assert_equal(snapshot, file_snapshot(root), 'Read-only check changed files')

  changed = messages.merge('Play.' => 'Nowa zasada.')
  assert_raises(GameRoomTranslationDocuments::StaleFiles) { GameRoomTranslationDocuments.sync(root, changed, check: true) }
  assert_equal(snapshot, file_snapshot(root), 'Stale document check wrote files')
  assert_equal([book_path], GameRoomTranslationDocuments.sync(root, changed))
  assert_equal('Nowa zasada.', JSON.parse(File.read(book_path))['sections'][0]['paragraphs'][0]['pl'])

  # Structural sources cannot be repaired from a translation catalog. Any
  # malformed source must stop the whole operation before the first write.
  later_path = File.join(root, 'tools/data/rulebooks/later.json')
  File.binwrite(later_path, File.binread(book_path))
  missing_source = { 'sections' => [{ 'title' => { 'pl' => 'No English source' }, 'paragraphs' => [] }] }
  [['truncated JSON {', JSON::ParserError],
   [JSON.generate(missing_source), KeyError]].each do |malformed, error|
    valid = File.binread(later_path)
    begin
      File.binwrite(later_path, malformed)
      snapshot = file_snapshot(root)
      [false, true].each do |check|
        assert_raises(error) { GameRoomTranslationDocuments.sync(root, messages, check: check) }
        assert_equal(snapshot, file_snapshot(root), 'Malformed structural source allowed partial writes')
      end
    ensure
      File.binwrite(later_path, valid)
    end
  end
end
puts 'Translated documents: PO authority, unchanged structure, plural alias, idempotency and no partial/check writes'
