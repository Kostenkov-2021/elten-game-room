require "json"
root = File.expand_path("../..", __dir__)
bytes = File.binread(File.join(root, "locale/PL.mo"))
count, originals, translations = bytes.byteslice(8, 12).unpack("V3")
catalog = count.times.to_h do |i|
  length, offset = bytes.byteslice(originals + i * 8, 8).unpack("V2")
  key = bytes.byteslice(offset, length).force_encoding("UTF-8")
  length, offset = bytes.byteslice(translations + i * 8, 8).unpack("V2")
  [key, bytes.byteslice(offset, length).force_encoding("UTF-8")]
end
paths = %w[games/scrabble.rb games/scrabble_ui.rb games/taboo.rb games/taboo_ui.rb
  lib/scrabble_rules.rb lib/game_surfaces/word_board.rb lib/game_surfaces/taboo_surface.rb
  games/yahtzee.rb games/ludo.rb games/farkle.rb __app.rb lib/participant_menu.rb lib/table_activity_repository.rb]
keys = paths.flat_map do |path|
  code = File.read(File.join(root, path), encoding: "UTF-8")
  code.scan(/(?<![\w])_\("((?:[^"\\]|\\.)*)"\)/m).flatten.map { |literal| JSON.parse('"' + literal + '"') } +
    code.scan(/n_\(\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"/m).map { |pair| pair.map { |literal| JSON.parse('"' + literal + '"') }.join("\0") }
end.uniq
missing = keys.reject { |key| catalog[key] && !catalog[key].empty? }
if ARGV.include?("--missing")
  puts JSON.pretty_generate(missing)
  exit
end
raise "Missing PL translations: #{missing.join("\n")}" unless missing.empty?
keys.each do |key|
  translated = catalog.fetch(key)
  raise "Invalid encoding: #{key}" unless translated.valid_encoding?
  translated.split("\0").each do |value|
    raise "Invalid placeholders: #{key}" unless value.scan(/%\{[^}]+\}/).sort == key.split("\0").first.scan(/%\{[^}]+\}/).sort
  end
end
puts "Release 2.0 localization: #{keys.length} strings, full game rules, placeholders and UTF-8: OK"
