require 'tmpdir'
require 'open3'
require 'rbconfig'
require_relative "../support/assertions"
include GameRoomTest::Assertions

generator = File.expand_path("../fixtures/generate_contracts.rb", __dir__)
Dir.mktmpdir('contract-authoring-') do |folder|
  # Refusal must precede loading any implementation from the reference checkout.
  sentinel = File.join(folder, 'sentinel')
  File.write(sentinel, 'golden values')
  output, status = Open3.capture2e(RbConfig.ruby, generator, '--source', 'missing-reference', '--write', folder)
  assert(!status.success? && output.include?('Corpus already exists'), 'generator replaced or loaded over existing fixtures')
  assert_equal(['sentinel'], Dir.children(folder))
  assert_equal('golden values', File.read(sentinel))
  output, status = Open3.capture2e(RbConfig.ruby, generator, '--write', File.join(folder, 'new'))
  assert(!status.success? && output.include?('--source') && !File.exist?(File.join(folder, 'new')), 'implicit implementation used as an oracle')
end
puts 'PASS contract authoring requires an explicit reference and a new version directory'
