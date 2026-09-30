require "tmpdir"
require "digest"
require_relative "../../tools/support/release_files"

def assert(value, message)
  raise message unless value
end

def must_reject(message)
  begin
    yield
  rescue RuntimeError, Errno::ENOENT
    return
  end
  raise message
end

repo = File.expand_path("../..", __dir__)
selected = GameRoomReleaseFiles.files(repo)
app_source = File.read(File.join(repo, '__app.rb'), encoding: 'UTF-8')
embedded_manifest = JSON.parse(app_source.split('=begin Elten3AppInfo', 2).last.split('=end', 2).first)
assert(embedded_manifest == JSON.parse(File.read(File.join(repo, 'manifest.json'), encoding: 'UTF-8')),
  'Embedded and standalone manifests differ, including the order of required assets')
assert(selected.grep(/\.rb\z/).length >= 187, "Runtime sources omitted")
%w[single race word-tower].each do |variant|
  path = "Audio/krowa-#{variant}.opus"
  assert(selected.include?(path), "Compressed Krowa music missing: #{variant}")
  bytes = File.binread(File.join(repo, path))
  assert(bytes.start_with?("OggS") && bytes.include?("OpusHead"), "Music is not Ogg Opus: #{variant}")
end
assert(!selected.include?("Audio/krowa-word-tower.mp3"), "Original music duplicated in release")
%w[content/scrabble_words_pl_data.rb games/krowa_support/noun_data.rb locale/PL.mo
   LICENSE content/QUIZ_DATA_NOTICE.md content/QUIZ_PL_SPORT_SOURCES.txt].each do |file|
  assert(selected.include?(file), "Required content omitted: #{file}")
end
%w[AGENTS.md CHANGELOG.md README.md CONTRIBUTING.md content/QUIZ_IMPORT_REPORT.json
   content/taboo_editorial.txt test/anything.rb tools/anything.rb tools/data/rulebooks/uno.json
   .git/config lib/.secret.rb Audio/original.opus.bak locale/authoring.json
   locale/PL.po locale/CS.po locale/game-room.pot tools/plural_forms.json].each do |file|
  assert(!GameRoomReleaseFiles.allowed?(file), "Development/private file admitted: #{file}")
end
%w[games/future_game.rb lib/future/service.rb content/future_data.rb Audio/future.opus
   locale/DE.mo content/FUTURE_NOTICE.md LICENSES/FUTURE.txt].each do |file|
  assert(GameRoomReleaseFiles.allowed?(file), "Future runtime asset blocked: #{file}")
end

Dir.mktmpdir("gr-release-test-") do |directory|
  source = File.join(directory, "source")
  Dir.mkdir(source)
  GameRoomReleaseFiles::REQUIRED_FILES.each do |path|
    FileUtils.mkdir_p(File.dirname(File.join(source, path)))
    File.binwrite(File.join(source, path), path == "manifest.json" ? '{"required_assets":{"sounds":["test"]}}' : "# fixture\n")
  end
  %w[Audio lib test tools docs].each { |path| FileUtils.mkdir_p(File.join(source, path)) }
  fixture_audio = "OggS\x00\xFFOpusHeadfixture".b
  File.binwrite(File.join(source, "Audio/test.opus"), fixture_audio)
  File.write(File.join(source, "lib/extra.rb"), "# runtime\n")
  File.write(File.join(source, "__app.rb"), "require_relative 'lib/extra'\n")
  %w[test/private.rb tools/private.rb docs/private.md].each { |path| File.write(File.join(source, path), "not shipped") }
  destination = File.join(directory, "release")
  paths = GameRoomReleaseFiles.stage(source, destination)
  assert(paths.include?("lib/extra.rb"), "Relative runtime dependency missing")
  assert(!File.exist?(File.join(destination, "test")), "Test folder distributed")
  assert(File.binread(File.join(destination, "Audio/test.opus")) == fixture_audio, "Binary resource changed")
  must_reject("Stage overwrote an existing directory") { GameRoomReleaseFiles.stage(source, destination) }
  must_reject("Stage allowed a directory inside source") { GameRoomReleaseFiles.stage(source, File.join(source, "release")) }
  File.write(File.join(source, "__app.rb"), "require_relative 'test/private'\n")
  must_reject("Dependency on excluded code ignored") { GameRoomReleaseFiles.files(source) }
  File.write(File.join(source, "__app.rb"), "require_relative 'lib/missing'\n")
  must_reject("Missing lazy dependency ignored") { GameRoomReleaseFiles.files(source) }
  File.write(File.join(source, "__app.rb"), "require_relative 'lib/extra'\n")
  File.binwrite(File.join(source, "Audio/future.wav"), "RIFFfixture")
  must_reject("Legacy-format audio was silently included or omitted") { GameRoomReleaseFiles.files(source) }
  File.delete(File.join(source, "Audio/future.wav"))
  File.binwrite(File.join(source, "Audio/future.opus"), "not opus")
  must_reject("Renaming a file was treated as encoding") { GameRoomReleaseFiles.files(source) }
  File.delete(File.join(source, "Audio/future.opus"))
  File.binwrite(File.join(source, "Audio/test.mp3"), "duplicate")
  must_reject("Ambiguous duplicate sound admitted") { GameRoomReleaseFiles.files(source) }
end
puts "PASS release selection: #{selected.length} production/license files, no developer files; exact copies, dependencies, safe staging and future assets"
