require "json"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"

root = File.expand_path("../..", __dir__)
Dir.mktmpdir("game-room-rule-source-") do |temporary|
  %w[tools games tools/data/rulebooks locale].each { |directory| FileUtils.mkdir_p(File.join(temporary, directory)) }
  FileUtils.cp(File.join(root, "tools/compile-rulebooks.rb"), File.join(temporary, "tools/compile-rulebooks.rb"))
  game = File.join(temporary, "games/example.rb")
  File.write(game, "module Example\n  class Game\n    def rule_sections\n      []\n    end\n  end\nend\n")
  book_path = File.join(temporary, "tools/data/rulebooks/example.json")
  output_path = File.join(temporary, 'games/generated/rulebooks/example.rb')
  manifest = {'example.json' => {'source' => 'games/example.rb', 'class' => 'Example', 'kind' => 'class', 'output' => 'games/generated/rulebooks/example.rb'}}
  File.write(File.join(temporary, 'tools/rulebook_sources.json'), JSON.generate(manifest))
  book = { "source" => "games/example.rb", "sections" => [{ "id" => "rules", "title" => { "en" => "Rules — overview" }, "paragraphs" => [{ "en" => "Choose %{count} cards." }] }] }
  File.write(book_path, JSON.generate(book), encoding: "UTF-8")
  File.binwrite(File.join(temporary, "locale/PL.po"), "TRANSLATOR WORK")
  File.binwrite(File.join(temporary, "locale/PL.mo"), "EXISTING RUNTIME")
  output, status = Open3.capture2e(RbConfig.ruby, File.join(temporary, "tools/compile-rulebooks.rb"))
  raise "English rule generation still requires inline Polish translations: #{output}" unless status.success?
  maintained = File.binread(game)
  compiled = File.binread(output_path)
  raise "English rule content was lost" unless compiled.include?('GameRoomRules.translate("Choose %{count} cards.")')
  book["sections"].first["title"]["pl"] = "POISONED OLD TRANSLATION"
  book["sections"].first["paragraphs"].first["pl"] = "POISONED OLD TRANSLATION"
  File.write(book_path, JSON.generate(book), encoding: "UTF-8")
  output, status = Open3.capture2e(RbConfig.ruby, File.join(temporary, "tools/compile-rulebooks.rb"))
  raise "English generator rejected ignored old translations: #{output}" unless status.success?
  raise "Polish fields changed generated English code" unless File.binread(output_path) == compiled
  raise 'Generating rules changed the maintained model' unless File.binread(game) == maintained
  raise "Rule generation overwrote the translator file" unless File.binread(File.join(temporary, "locale/PL.po")) == "TRANSLATOR WORK"
  raise "Rule generation still overwrites MO from JSON" unless File.binread(File.join(temporary, "locale/PL.mo")) == "EXISTING RUNTIME"
  raise "Rule generation recreated the old translation source" if File.exist?(File.join(temporary, "locale/rules-rewrite-pl.json"))
end
puts "English-only rule generation ignores Polish mirrors and never writes PO/MO"
