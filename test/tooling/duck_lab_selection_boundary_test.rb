require 'json'
require 'open3'
require 'rbconfig'
require_relative '../support/assertions'
include GameRoomTest::Assertions

root = File.expand_path('../..', __dir__)
script = 'test/tooling/duck_racing_lab_test.rb'
environment = {'DUCK_LAB_REPORT' => nil}
output, status = Open3.capture2e(environment.merge('DUCK_LAB_CASE' => 'no-such-audit-case-54'),
  RbConfig.ruby, script, chdir: root)
assert(!status.success?, "An empty Duck lab selection passed: #{output}")
assert(output.include?('No Duck lab tests match the requested filter'),
  "Empty selection failed for a different reason: #{output}")

output, status = Open3.capture2e(environment.merge('DUCK_LAB_CASE' => 'shared payload decoder'),
  RbConfig.ruby, script, chdir: root)
assert(status.success?, "A real filtered case failed: #{output}")
report = JSON.parse(output)
assert_equal(1, report.fetch('tests'))
assert_equal(1, report.fetch('passed'))
assert_equal(0, report.fetch('failures'))
puts 'PASS Duck lab selection: a nonexistent filter fails; an actual single case executes and reports its result'
