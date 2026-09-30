require "ripper"

root = File.expand_path("../..", __dir__)
helpers = %w[_ n_ p_ np_ s_ ns_]
errors = []
visit = nil
visit = lambda do |node, active, path|
  next unless node.is_a?(Array)
  if node[0] == :program || node[0] == :bodystmt
    local = active
    node[1].to_a.each do |statement|
      if statement.is_a?(Array) && statement[0] == :command && statement.dig(1, 1) == "using"
        local = true if statement.flatten.include?("GameRoomLocalization") && statement.flatten.include?("Translations")
      end
      visit.call(statement, local, path)
    end
    node.drop(2).each { |child| visit.call(child, local, path) }
  else
    if [:fcall, :vcall, :command].include?(node[0]) && helpers.include?(node.dig(1, 1)) && !active
      errors << "#{path}:#{node.dig(1, 2, 0)} #{node.dig(1, 1)}"
    end
    node.each { |child| visit.call(child, active, path) if child.is_a?(Array) }
  end
end
paths = [File.join(root, "__app.rb")] + %w[games lib content].flat_map { |directory| Dir[File.join(root, directory, "**/*.rb")] }
paths.each do |path|
  next if File.basename(path).start_with?("game_room_localization", "game_room_plural_rule")
  source = File.read(path, encoding: "UTF-8")
  next unless source.match?(/\b(?:n_|p_|np_|s_|ns_|_)\s*\(/)
  tree = Ripper.sexp(source)
  raise "Cannot parse #{path}" unless tree
  visit.call(tree, false, path.delete_prefix(root + "/"))
end
abort "Game Room translation calls still use the host dictionary:\n#{errors.join("\n")}" unless errors.empty?
puts "All Game Room translation call scopes are independent of the host"
