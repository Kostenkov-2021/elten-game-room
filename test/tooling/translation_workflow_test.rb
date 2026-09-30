require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"
require "json"

root = File.expand_path("../..", __dir__)
command = File.join(root, "tools/translations.rb")
raise "There is no single PO authoring workflow" unless File.file?(command)

def assert(condition, message)
  raise message unless condition
end

def run_translation(command, root, *arguments)
  env = { "BUNDLE_GEMFILE" => File.join(File.dirname(command), "Gemfile.i18n") }
  output, status = Open3.capture2e(env, RbConfig.ruby, command, "--root", root, *arguments)
  [output, status]
end

Dir.mktmpdir("game-room-po-workflow-") do |temporary|
  %w[locale tools tools/data/rulebooks games lib content].each { |directory| FileUtils.mkdir_p(File.join(temporary, directory)) }
  FileUtils.cp(File.join(root, "locale/PL.mo"), File.join(temporary, "locale/PL.mo"))
  File.write(File.join(temporary, "__app.rb"), "module Example\n  def label; _(\"New translator label\"); end\nend\n")
  output, status = run_translation(command, temporary, "import-mo")
  assert(status.success?, "existing translations could not be imported: #{output}")
  po = File.join(temporary, "locale/PL.po")
  assert(File.file?(po) && File.read(po, encoding: "UTF-8").include?('msgstr "Szachy"'), "MO-only translations did not reach the editable PO")
  output, status = run_translation(command, temporary, "update")
  assert(status.success?, "source messages could not be updated: #{output}")
  assert(File.read(po, encoding: "UTF-8").include?('msgid "New translator label"'), "a new UI label is missing from the translator's file")
  template = File.join(temporary, "locale/game-room.pot")
  assert(File.file?(template), "there is no template for another translator")
  before = File.binread(po)
  output, status = run_translation(command, temporary, "compile")
  assert(status.success?, "PO could not be compiled: #{output}")
  assert(File.binread(po) == before, "compilation edited the translator's PO")
  mo = File.binread(File.join(temporary, "locale/PL.mo"))
  output, status = run_translation(command, temporary, "check")
  assert(status.success? && File.binread(po) == before && File.binread(File.join(temporary, "locale/PL.mo")) == mo, "read-only verification changed outputs: #{output}")
  output, status = run_translation(command, temporary, "new", "CS", "--name", "čeština")
  assert(status.success?, "a Czech translator file could not be created: #{output}")
  czech = File.join(temporary, "locale/CS.po")
  assert(File.file?(czech) && !File.exist?(File.join(temporary, "locale/CS.mo")), "creating a draft installed an untranslated UI language")
  assert(File.read(czech, encoding: "UTF-8").include?('msgid "New translator label"'), "new-language drafts miss source messages")
  snapshot = File.binread(czech)
  output, status = run_translation(command, temporary, "new", "CS", "--name", "čeština")
  assert(!status.success? && File.binread(czech) == snapshot, "creating a language overwrote a translator's work")
  output, status = run_translation(command, temporary, "compile", "CS")
  assert(status.success? && File.file?(File.join(temporary, "locale/CS.mo")), "a Czech draft with empty translations cannot be compiled for fallback: #{output}")
  { "DE" => "Deutsch", "JA" => "日本語", "AR" => "العربية" }.each do |code, name|
    output, status = run_translation(command, temporary, "new", code, "--name", name)
    assert(status.success?, "standard plural defaults failed for #{code}: #{output}")
    output, status = run_translation(command, temporary, "compile", code)
    assert(status.success?, "blank plural variants failed for #{code}: #{output}")
  end
  output, status = run_translation(command, temporary, "check")
  assert(status.success?, "automatic catalog discovery failed: #{output}")
  %w[AR CS DE JA PL].each do |code|
    assert(output.include?("Verified #{code}.po"), "check silently omitted #{code}: #{output}")
  end
  assert(Dir.glob('*.json', base: File.join(temporary, 'locale')).empty?, 'Translation commands recreated legacy JSON catalogs')
  output, status = run_translation(command, temporary, "new", "../CS", "--name", "čeština")
  assert(!status.success?, "an unsafe language code was accepted")
  output, status = run_translation(command, temporary, "import-mo", "PL")
  assert(!status.success? && File.binread(po) == before, "re-import overwrote the authoritative PO")
end
puts "One-file translation workflow: complete import, update, compile/check, Czech draft and overwrite/path protection passed"
