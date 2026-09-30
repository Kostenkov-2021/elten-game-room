require 'tmpdir'
require 'open3'
require 'json'
require 'rbconfig'

def assert(value, message); raise message unless value; end
runner = File.expand_path("../run.rb", __dir__)
Dir.mktmpdir('game-room-runner-') do |folder|
  scripts = {
    '01_pass.rb' => 'SHARED_TEST_STATE = true; puts "passed"',
    '02_fail.rb' => 'raise "intentional assertion"',
    '03_skip.rb' => 'puts "SKIP missing dependency"',
    '04_timeout.rb' => 'sleep 60',
    '05_isolated.rb' => 'raise "leaked globals" if defined?(SHARED_TEST_STATE); puts "isolation checked"'
  }
  scripts.each { |name, contents| File.write(File.join(folder, name), contents) }
  report = File.join(folder, 'report.json')
  _output, status = Open3.capture2e(RbConfig.ruby, runner, '--timeout', '1', '--report', report, File.join(folder, '*.rb'))
  assert(!status.success?, 'failures/skips/timeouts reported success')
  results = JSON.parse(File.read(report))
  assert(results.map { |item| item['outcome'] } == %w[passed failed skipped timeout passed], 'runner did not continue or classify each script')
  assert(results[1]['output'].include?('intentional assertion') && results[4]['output'].include?('isolation checked'), 'failure detail or later tests lost')
  _output, status = Open3.capture2e(RbConfig.ruby, runner, '--allow-skip', File.join(folder, '03_skip.rb'))
  assert(status.success?, 'explicit optional skip rejected')
  output, status = Open3.capture2e(RbConfig.ruby, runner, File.join(folder, 'missing.rb'), File.join(folder, '01_pass.rb'))
  assert(!status.success? && output.include?('No tests matched'), 'missing requested test silently omitted')
end
puts 'Runner: independent processes, continued failures, explicit skips, timeout, report and missing selection passed'
