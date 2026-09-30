require "open3"
require "rbconfig"
require 'prism'

def assert(value, message); raise message unless value; end
root = File.expand_path("../..", __dir__)
paths = Dir.glob('test/**/*.rb', base: root)
assert(!paths.empty?, 'No test sources were checked')
imports = paths.flat_map do |relative|
  path = File.join(root, relative)
  found = []
  nodes = [Prism.parse_file(path).value]
  while (node = nodes.pop)
    nodes.concat(node.compact_child_nodes)
    next unless node.is_a?(Prism::CallNode) && %i[require_relative require load].include?(node.name)
    argument = node.arguments&.arguments&.first
    if argument.is_a?(Prism::StringNode) && argument.unescaped.match?(/_test(?:\.rb)?\z/)
      found << "#{path}:#{node.location.start_line}"
    end
  end
  found
end
assert(imports.empty?, "A test still imports another scenario: #{imports.join(', ')}")
%w[audio_ball_point_audio axel_pong_doubles_lobby audio_tutorial_native table_lifecycle_controls_2 no_bot_table_control post_233_ping table_notice_presentation game_option_encoding score_announcements card_reshuffle translation_reference].each do |name|
  helper = File.join(root, "test/support/#{name}.rb")
  output, status = Open3.capture2e(RbConfig.ruby, "-r", helper, "-e", 'puts "fixture loaded"')
  assert(status.success? && output.lines.last.to_s.strip == "fixture loaded", "#{name}: fixture failed: #{output}")
  assert(!output.match?(/^(?:PASS|FAIL|All |passed:|\[\d+\/)/), "#{name}: import ran another scenario: #{output}")
end
puts "PASS fixture boundaries: no test imports, native/point/lifecycle/ping/notification helpers load without scenarios"
