require 'open3'
require 'rbconfig'
require_relative '../support/assertions'
include GameRoomTest::Assertions

root = File.expand_path('../..', __dir__)
source = <<~'RUBY'
  require_relative 'test/tournaments/drafts_test'
  require_relative 'test/tournaments/local_test_tables_test'
  raise 'Missing actual parent test definitions' unless defined?(TournamentDraftsTest) && defined?(TournamentLocalTestTablesTest)
  puts 'DEFINITIONS_ONLY'
RUBY
# The previous importer needed this filter to avoid running the entire local
# table suite as a side effect. Even one unrelated scenario must not run here.
output, status = Open3.capture2e({'LOCAL_TABLES_TEST' => 'test_allowlist_and_reserved_metadata'},
  RbConfig.ruby, '-e', source, chdir: root)
assert(status.success?, "Actual parent definitions could not be loaded: #{output}")
assert_equal("DEFINITIONS_ONLY\n", output, 'Loading cleanup subjects executed an unrelated parent scenario')
output, status = Open3.capture2e({'LOCAL_TABLES_TEST' => 'test_allowlist_and_reserved_metadata'},
  RbConfig.ruby, 'test/tournaments/local_test_tables_test.rb', chdir: root)
assert(status.success?, "Direct local-table selection failed: #{output}")
assert(output.lines.map(&:strip).include?('PASS test_allowlist_and_reserved_metadata'),
  "The direct entry point stopped executing its selected case: #{output}")
puts 'PASS local parent import: definitions only on require; direct selected local-table scenario still executes'
