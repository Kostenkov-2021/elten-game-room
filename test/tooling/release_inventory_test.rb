require 'tmpdir'
require_relative '../support/assertions'
require_relative '../../tools/stage-release'
include GameRoomTest::Assertions

Dir.mktmpdir('release-inventory') do |root|
  source = File.join(root, 'source')
  GameRoomReleaseFiles::REQUIRED_FILES.each do |relative|
    path = File.join(source, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, relative == 'manifest.json' ? '{}' : '# fixture')
  end
  inventory = File.join(root, 'inventory.json')
  original = GameRoomReleaseStage.run(source: source, manifest: inventory)
  assert_equal(original, GameRoomReleaseStage.run(source: source, check: true, manifest: inventory))
  assert_equal(original, GameRoomReleaseFiles.snapshot(source), 'inventory depends on timestamps or absolute paths')
  assert_raises(RuntimeError) { GameRoomReleaseStage.run(source: source, manifest: inventory) }
  File.write(File.join(source, '__app.rb'), '# changed')
  assert_raises(RuntimeError) { GameRoomReleaseStage.run(source: source, check: true, manifest: inventory) }
  assert_raises(ArgumentError) { GameRoomReleaseStage.run(source: source, check: true) }
end
puts 'PASS reproducible runtime inventories'
