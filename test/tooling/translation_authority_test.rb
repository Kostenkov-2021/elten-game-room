require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"
require "json"
require_relative "../../tools/support/translation_catalog"

root = File.expand_path("../..", __dir__)
cli = File.join(root, "tools/translations.rb")

def assert(condition, message)
  raise message unless condition
end

def run_tool(script, *arguments)
  env = { "BUNDLE_GEMFILE" => File.join(File.dirname(script), "Gemfile.i18n") }
  output, status = Open3.capture2e(env, RbConfig.ruby, script, *arguments)
  raise "Translation command failed: #{output}" unless status.success?
  output
end

Dir.mktmpdir("game-room-po-authority-") do |temporary|
  %w[tools/support lib locale tools/data/rulebooks games content].each { |directory| FileUtils.mkdir_p(File.join(temporary, directory)) }
  %w[translations.rb support/translation_catalog.rb support/translation_extractor.rb support/translation_documents.rb compile-rulebooks.rb Gemfile.i18n Gemfile.i18n.lock plural_forms.json].each do |name|
    FileUtils.cp(File.join(root, "tools", name), File.join(temporary, "tools", name))
  end
  FileUtils.cp(File.join(root, "lib/game_room_plural_rule.rb"), File.join(temporary, "lib/game_room_plural_rule.rb"))
  FileUtils.cp(File.join(root, "locale/PL.po"), File.join(temporary, "locale/PL.po"))
  File.write(File.join(temporary, "__app.rb"), 'module UI; def label; _("Settings"); end; end')
  File.write(File.join(temporary, "games/example.rb"), "module Example\n  class Game\n    def rule_sections\n      []\n    end\n  end\nend\n")
  book = { "source" => "games/example.rb", "sections" => [{ "id" => "rules", "title" => { "en" => "Rules", "pl" => "OLD" }, "paragraphs" => [{ "en" => "It is your turn.", "pl" => "OLD" }] }] }
  File.write(File.join(temporary, "tools/data/rulebooks/example.json"), JSON.generate(book))
  manifest = { "example.json" => { "source" => "games/example.rb", "class" => "Example", "kind" => "class", "output" => "games/generated/rulebooks/example.rb" } }
  File.write(File.join(temporary, "tools/rulebook_sources.json"), JSON.generate(manifest))
  File.binwrite(File.join(temporary, "locale/PL.mo"), "CORRUPT OLD OUTPUT")
  po_path = File.join(temporary, "locale/PL.po")
  po = GameRoomTranslationCatalog.read_po(po_path)
  po["Settings"].msgstr = "Ustawienia tłumacza"
  po["It is your turn."].msgstr = "Teraz twój ruch."
  po["cat_head_tail", "Roll"].msgstr = "Rzuć teraz"
  po["%{count} question"].msgstr = "%{count} pytanko\0%{count} pytanka\0%{count} pytanek"
  GameRoomTranslationCatalog.write_po(po, po_path)
  expected = GameRoomTranslationCatalog.message_map(po)
  commands = [
    [File.join(temporary, "tools/translations.rb"), "compile", "PL"],
    [File.join(temporary, "tools/compile-rulebooks.rb")],
    [File.join(temporary, "tools/translations.rb"), "update"],
    [File.join(temporary, "tools/translations.rb"), "compile", "PL"]
  ]
  commands.each do |arguments|
    run_tool(*arguments)
    current = GameRoomTranslationCatalog.message_map(GameRoomTranslationCatalog.read_po(po_path))
    assert(expected.all? { |key, value| current[key] == value }, "a compiler/update command replaced translator changes or dropped history")
    mo = GetText::MO.open(File.join(temporary, "locale/PL.mo"))
    %W[Settings cat_head_tail\u0004Roll].each do |key|
      assert(mo.fetch(key).b == expected.fetch(key).b, "compiled wording reverted: #{key.inspect}")
    end
    assert(mo.fetch("%{count} question\0%{count} questions").b == expected.fetch("%{count} question\0%{count} questions").b, "compiled plurals reverted")
  end
  assert(JSON.parse(File.read(File.join(temporary, "tools/data/rulebooks/example.json")))["sections"][0]["paragraphs"][0]["pl"] == "Teraz twój ruch.", "rule translations require another editable file")
  File.write(File.join(temporary, "locale/unrelated.json"), JSON.generate({ "Settings" => "UNRELATED" }))
  run_tool(File.join(temporary, "tools/translations.rb"), "compile", "PL")
  assert(GetText::MO.open(File.join(temporary, "locale/PL.mo")).fetch("Settings").b == "Ustawienia tłumacza".b, "unrelated JSON can clobber PO")
  assert(Dir.children(File.join(temporary, 'locale')).sort == %w[PL.mo PL.po game-room.pot unrelated.json], 'Compilation created redundant catalogs')
  assert(JSON.parse(File.read(File.join(temporary, 'locale/unrelated.json'))) == { 'Settings' => 'UNRELATED' }, 'Compilation overwrote an unrelated file')
  run_tool(File.join(temporary, "tools/translations.rb"), "check", "PL")
end
puts "One authoritative PO survives every compiler/update command; contexts and plurals are preserved, unrelated files are ignored"
