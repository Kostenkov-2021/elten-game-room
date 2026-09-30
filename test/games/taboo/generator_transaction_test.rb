require 'json'
require 'digest'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'

def assert(value, message); raise message unless value; end
repo = File.expand_path("../../..", __dir__)
Dir.mktmpdir('taboo-generator-test-') do |scratch|
  %w[tools lib content].each { |name| FileUtils.mkdir_p(File.join(scratch, name)) }
  FileUtils.cp(File.join(repo, 'tools/build-taboo-cards.rb'), File.join(scratch, 'tools/build-taboo-cards.rb'))
  %w[game_content.rb game_room_localization.rb game_room_plural_rule.rb].each do |name|
    FileUtils.cp(File.join(repo, 'lib', name), File.join(scratch, 'lib', name))
  end
  FileUtils.cp_r(File.join(repo, 'lib/vendor'), File.join(scratch, 'lib/vendor'))
  FileUtils.cp(File.join(repo, 'content/languages.rb'), File.join(scratch, 'content/languages.rb'))
  rows = 500.times.map { |index| ["PL #{index}", 'one;two;three;four;five', "EN #{index}", 'one;two;three;four;five'] }
  editorial = File.join(scratch, 'content/taboo_editorial.txt')
  write_rows = ->(data) { File.write(editorial, data.map { |row| row.join('|') }.join("\n"), encoding: 'UTF-8') }
  script = File.join(scratch, 'tools/build-taboo-cards.rb')
  outputs = %w[taboo_cards_pl_data.rb taboo_cards_en_data.rb taboo_cards.rb].map { |name| File.join(scratch, 'content', name) }
  fingerprint = -> { outputs.map { |path| File.exist?(path) ? Digest::SHA256.file(path).hexdigest : nil } }
  run = lambda do |prefix = ''|
    Open3.capture2e(RbConfig.ruby, '-e', "#{prefix}\nload #{script.inspect}")
  end
  write_rows.call(rows)
  output, status = run.call
  assert(status.success?, output)
  before = fingerprint.call
  [0, 2].each do |column|
    invalid = rows.map(&:dup)
    invalid[0][0] = 'Changed PL target'
    invalid[1][column] = invalid[0][column]
    write_rows.call(invalid)
    output, status = run.call
    assert(!status.success? && output.include?('Duplicate targets'), 'Invalid language was accepted')
    assert(fingerprint.call == before, 'Validation changed an output')
  end
  changed = rows.map(&:dup)
  changed[0][0], changed[0][2] = 'Changed PL target', 'Changed EN target'
  write_rows.call(changed)
  outputs.drop(1).each do |fail_at|
    prefix = <<~RUBY
      class << File
        alias_method :real_rename, :rename
        def rename(source, target)
          if target == #{fail_at.inspect} && !@failed_once
            @failed_once = true
            raise IOError, 'Injected replacement failure'
          end
          real_rename(source, target)
        end
      end
    RUBY
    output, status = run.call(prefix)
    assert(!status.success? && output.include?('Injected replacement failure'), 'Write failure was hidden')
    assert(fingerprint.call == before, 'Rollback left a partial bilingual pack')
    assert(Dir.glob(File.join(scratch, 'content', '.taboo-*')).empty?, 'Successful rollback left temporary files')
  end
  output, status = run.call
  assert(status.success? && fingerprint.call.zip(before).all? { |a, b| a != b }, 'Successful complete rebuild failed')
  code = "require #{File.join(scratch, 'content/languages.rb').inspect}; require #{outputs.last.inspect}; " +
    "%w[pl-pl en].each { |lang| raise 'Wrong count' unless GameRoomContent.registry.pack('taboo.general.' + lang + '.v1').data.length == 500 }"
  output, status = Open3.capture2e(RbConfig.ruby, '-e', code)
  assert(status.success?, output)

  # If restoring the first file also fails, retain a usable backup after the
  # generator process exits instead of letting Tempfile's finalizer erase it.
  saved_first = File.binread(outputs.first)
  changed[0][0] = 'Another PL target'
  write_rows.call(changed)
  prefix = <<~RUBY
    class << File
      alias_method :real_rename, :rename
      def rename(source, target)
        if target == #{outputs[1].inspect} || File.basename(source).start_with?('.taboo-backup-')
          raise IOError, 'Injected rollback failure'
        end
        real_rename(source, target)
      end
    end
  RUBY
  output, status = run.call(prefix)
  assert(!status.success? && output.include?('Taboo output rollback failed:') && output.include?('Recovery files:'),
    'A failed rollback did not report recovery files')
  backups = Dir.glob(File.join(scratch, 'content', '.taboo-backup-*'))
  assert(backups.any? { |path| File.binread(path) == saved_first }, 'Failed rollback lost the original bytes on process exit')
end
puts 'PASS Taboo generator: both invalid languages, failures at second/third replacement, exact rollback, both packs load and recovery backup survives rollback failure'
