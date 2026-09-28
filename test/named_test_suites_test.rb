require_relative "../tools/run-tests"
require "tmpdir"
require "stringio"

def assert(value, message); raise message unless value; end
root = GameRoomTestRunner::ROOT
suites = {
  "run-five-game-tests" => [25, "test/new_games_116_test.rb", "tools/check-five-game-translations.rb"],
  "run-connection-recovery-tests" => [18, "test/connection_recovery_test.rb", "test/packaged_rules_encoding_test.rb"],
  "run-quiz-tests" => [31, "test/quiz_data_cleanup_test.rb", "test/synchronization_regressions_test.rb"],
  "run-audit-212-tests" => [40, "test/audit_212_rules_and_decisions_test.rb", "tools/check-five-game-translations.rb"]
}
suites.each do |name, (count, first, last)|
  output, status = Open3.capture2e(RbConfig.ruby, File.join(root, "tools/#{name}.rb"), "--list")
  assert(status.success?, "#{name}: listing failed: #{output}")
  paths = output.lines.map(&:strip)
  assert(paths.length == count && paths.first == first && paths.last == last, "#{name}: selection/translation check changed: #{paths.inspect}")
  assert(paths.uniq == paths, "#{name}: duplicate entries")
end

output, status = Open3.capture2e(RbConfig.ruby, File.join(root, 'tools/run-quiz-tests.rb'), '--historical-audit', '--list')
paths = output.lines.map(&:strip)
historical = %w[quiz_factual_audit quiz_recovery_audit witcher_medium_audit].map { |name| "test/historical/#{name}_test.rb" }
assert(status.success? && paths.length == 34 && paths.last(3) == historical && paths.uniq == paths,
  'explicit historical quiz selection lost provenance checks')
assert((GameRoomTestRunner.expand(['test/*_test.rb']).map { |entry| entry[:script] } & historical).empty?,
  'private audit evidence is required by the portable suite')

Dir.mktmpdir("game-room-named-suite-") do |folder|
  preload = File.join(folder, "preload.rb")
  scenario = File.join(folder, "scenario.rb")
  check = File.join(folder, "additional.rb")
  File.write(preload, "NAMED_SUITE_PRELOADED = true")
  File.write(scenario, 'raise "missing preload" unless NAMED_SUITE_PRELOADED; raise "wrong env" unless ENV["GAME_ROOM_FIVE_GAMES_ONLY"] == "1"; raise "wrong args" unless ARGV == ["package"]; puts "scenario checked"')
  File.write(check, 'raise "suite env escaped" if ENV["GAME_ROOM_FIVE_GAMES_ONLY"] == "1"; puts "additional checked"')
  saved = ENV.delete("GAME_ROOM_FIVE_GAMES_ONLY")
  begin
    entries = [{script: scenario, env: {"GAME_ROOM_FIVE_GAMES_ONLY" => "1"}, ruby_args: ["-r", preload], args: ["package"]}, check]
    results = GameRoomTestRunner.run(entries, output: StringIO.new)
    assert(GameRoomTestRunner.success?(results) && results.length == 2, "suite execution lost preload/environment/args or additional check: #{results.inspect}")
    assert(results.first[:output].include?("scenario checked") && results.last[:output].include?("additional checked"), "per-script output missing")
    listed = StringIO.new
    original_stdout = $stdout
    $stdout = listed
    begin
      assert(GameRoomTestRunner.cli(["--list", File.join(folder, "legacy.json")], tests: [scenario], legacy_report: true) == 0, "legacy report rejected")
    ensure
      $stdout = original_stdout
    end
    assert(listed.string.lines.map(&:strip) == [scenario] && !File.exist?(File.join(folder, "legacy.json")), "list executed or wrote a report")
  ensure
    ENV["GAME_ROOM_FIVE_GAMES_ONLY"] = saved
  end
end
puts "PASS named suites: exact selections, extra translation check, shared execution, environment, preload, arguments and legacy report"
