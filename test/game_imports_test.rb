require 'open3'
require 'rbconfig'
require_relative 'support/assertions'
include GameRoomTest::Assertions

# Each model must declare dependencies instead of borrowing the application's
# earlier requires. A separate process prevents another model hiding mistakes.
root = File.expand_path('..', __dir__)
models = File.readlines(File.join(root, 'games/catalog.rb')).filter_map do |line|
  line[/^require_relative "([^"]+)"/, 1]
end
models.each do |name|
  source = <<~RUBY
    require_relative './games/#{name}'
    abort 'native UI loaded' if defined?(GameRoomUI::Form) || defined?(Form)
  RUBY
  output, status = Open3.capture2e(RbConfig.ruby, '-e', source, chdir: root)
  assert(status.success?, "#{name} cannot load independently:\n#{output}")
end
puts "PASS independent headless imports: #{models.length} entries"
