require 'tmpdir'
require 'open3'
require 'rbconfig'
require_relative "../../support/assertions"
require_relative "../../../tools/spades"
include GameRoomTest::Assertions

script = File.expand_path("../../../tools/spades.rb", __dir__)
Dir.mktmpdir('spades-workflow-') do |folder|
  profile = SpadesLearning::ARRANGEMENT_PROFILES.keys.first
  trained = File.join(folder, 'training.json')
  evaluated = File.join(folder, 'evaluation.json')
  output, status = Open3.capture2e(RbConfig.ruby, script, 'train', '--profiles', profile,
    '--score-limits', '100', '--max-series', '1', '--generations', '1', '--population', '1',
    '--evaluation-seeds', '1', '--validation-seeds', '1', '--holdout-seeds', '1',
    '--training-max-actions', '1', '--validation-max-actions', '1', '--output', trained)
  assert_equal(2, status.exitstatus, "incomplete training was not reported: #{output}")
  campaign = JSON.parse(File.read(trained))
  assert_equal('spades-campaign-v1', campaign.fetch('format'))
  assert_equal([profile], campaign.fetch('arrangements').map { |item| item.fetch('arrangement') })
  assert_equal(false, campaign.fetch('arrangements').first.fetch('accepted'), 'unfinished holdout selected new weights')
  assert_equal(SpadesLearning::PolicySet.default.to_h, campaign.fetch('selected_profiles'), 'rejected candidate changed runtime defaults')

  output, status = Open3.capture2e(RbConfig.ruby, script, 'evaluate', '--report', trained,
    '--profiles', profile, '--score-limits', '100', '--seeds', '1', '--max-actions', '1',
    '--skip-calibration', '--output', evaluated)
  assert_equal(2, status.exitstatus, "incomplete evaluation was not reported: #{output}")
  report = JSON.parse(File.read(evaluated))
  result = report.fetch('arrangements').first
  assert_equal('spades-evaluation-v1', report.fetch('format'))
  assert(result.fetch('incomplete_games').positive?, 'missing incomplete game count')
  assert_equal(1, result.fetch('average_actions'), 'action budget was ignored')
  assert(result['candidate_calibration'].nil?, 'disabled calibration still ran')

  output, status = Open3.capture2e(RbConfig.ruby, script, 'evaluate', '--report', trained,
    '--profiles', profile, '--score-limits', '30', '--seeds', '1')
  assert_equal(0, status.exitstatus, "complete evaluation failed: #{output}")
  complete = JSON.parse(output).fetch('arrangements').first
  [complete, complete.fetch('candidate_calibration'), complete.fetch('baseline_calibration')].each do |evaluation|
    assert_equal(3, evaluation.fetch('games'), 'evaluation/calibration did not rotate each seat')
    assert_equal(0, evaluation.fetch('incomplete_games'), 'complete games were truncated')
    assert(evaluation.fetch('average_rounds').positive?, 'no completed rounds were evaluated')
  end

  before = File.binread(evaluated)
  output, status = Open3.capture2e(RbConfig.ruby, script, 'evaluate', '--report', trained, '--output', evaluated)
  assert_equal(1, status.exitstatus)
  assert(output.include?('Output already exists') && File.binread(evaluated) == before, 'report was overwritten')
  [['evaluate'], ['train', '--profiles', 'missing'], ['train', '--population', '0'], ['train', 'stray']].each do |arguments|
    _output, status = Open3.capture2e(RbConfig.ruby, script, *arguments)
    assert_equal(1, status.exitstatus, "invalid command accepted: #{arguments.inspect}")
  end
end
puts 'PASS Spades CLI: real bounded campaign/evaluation, explicit incomplete results, validation and report preservation'
