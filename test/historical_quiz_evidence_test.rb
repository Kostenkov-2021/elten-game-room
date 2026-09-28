require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'
require_relative 'support/historical_quiz_evidence'

def assert(value, message)
  raise message unless value
end

Dir.mktmpdir('game-room-missing-evidence-') do |folder|
  environment = {'GAME_ROOM_QUIZ_AUDIT_ROOT' => folder}
  %w[quiz_factual_audit quiz_recovery_audit witcher_medium_audit].each do |name|
    output, status = Open3.capture2e(environment, RbConfig.ruby, File.join(__dir__, 'historical', "#{name}_test.rb"))
    assert(!status.success? && output.include?('Historical quiz evidence is unavailable.'), 'Missing audit was not explained or passed')
    HistoricalQuizEvidence::REQUIRED_FILES.each { |path| assert(output.include?(path), 'Missing report omitted') }
  end
  # A complete set of files still has to parse and pass every audit assertion.
  HistoricalQuizEvidence::REQUIRED_FILES.each do |path|
    target = File.join(folder, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, 'invalid JSON')
  end
  output, status = Open3.capture2e(environment, RbConfig.ruby, File.join(__dir__, 'historical/quiz_recovery_audit_test.rb'))
  assert(!status.success? && output.include?('JSON::ParserError'), 'Corrupt audit evidence was silently skipped')

  # The normal Witcher scenario must work independently of external reports.
  guard = File.join(folder, 'forbid_private_reports.rb')
  File.write(guard, <<~RUBY)
    module ForbidPrivateQuizReports
      def read(path, *args, **options)
        raise 'Portable test accessed private diagnostics' if path.to_s.tr('\\\\', '/').include?('/diagnostics/')
        super
      end
    end
    File.singleton_class.prepend(ForbidPrivateQuizReports)
  RUBY
  output, status = Open3.capture2e(environment, RbConfig.ruby, '-r', guard, File.join(__dir__, 'witcher_medium_split_test.rb'))
  assert(status.success? && output.include?('Witcher medium split tests passed'), "Portable split test reads private evidence: #{output}")
end
puts 'Historical evidence: explicit requirements, no false pass/corruption bypass, portable Witcher split independent'
