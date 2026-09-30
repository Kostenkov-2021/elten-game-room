require 'tmpdir'
require_relative "../support/assertions"
require_relative "../../tools/stage-release"
include GameRoomTest::Assertions

Dir.mktmpdir('gr-stage-') do |root|
  source = File.join(root, 'source')
  GameRoomReleaseFiles::REQUIRED_FILES.each do |relative|
    path = File.join(source, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, relative == 'manifest.json' ? '{}' : '# fixture')
  end
  # No write may begin when the sidecar is inside (or is) the staging tree.
  destinations = [File.join(root, 'out')]
  manifests = ->(destination) { [destination, File.join(destination, 'lib/inventory.rb')] }
  if File::ALT_SEPARATOR == '\\'
    destinations << File.join(root, 'OUT')
  end
  destinations.each do |destination|
    manifests.call(File.join(root, 'out')).each do |manifest|
      assert_raises(ArgumentError) { GameRoomReleaseStage.run(source: source, destination: destination, manifest: manifest) }
      assert(!File.exist?(destination), 'invalid sidecar left a partial staging tree')
    end
  end
  destination = File.join(root, 'out')
  assert_raises(ArgumentError) do
    GameRoomReleaseStage.run(source: source, destination: destination, manifest: File.join(root, 'missing/inventory.json'))
  end
  assert(!File.exist?(destination), 'missing sidecar parent left a partial staging tree')
  if File::ALT_SEPARATOR == '\\'
    assert_raises(RuntimeError) { GameRoomReleaseFiles.stage(source, File.join(root, 'SOURCE', 'nested')) }
    assert(!File.exist?(File.join(source, 'nested')), 'case alias allowed staging inside source')
  end
  inventory = File.join(root, 'inventory.json')
  expected = GameRoomReleaseStage.run(source: source, destination: destination, manifest: inventory)
  assert_equal(expected, GameRoomReleaseStage.run(source: destination, manifest: inventory, check: true))
end
puts 'PASS release inventory stays outside staging, including Windows case aliases'
