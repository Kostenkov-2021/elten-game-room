require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'zip'
require_relative '../support/host_source'
require_relative '../support/log'
require_relative '../support/assertions'
require_relative '../../tools/support/release_files'
require_relative '../../lib/game_room_localization'
require EltenTestHost.file('src/eapi/program.rb')
include GameRoomTest::Assertions

root = File.expand_path('../..', __dir__)
locale = File.join(root, 'locale')
manifest = JSON.parse(File.read(File.join(root, 'manifest.json'), encoding: 'UTF-8'))
embedded = Programs::CodeManifestParser.parse(File.binread(File.join(root, '__app.rb')), '__app.rb')
languages = manifest.fetch('supported_languages').map(&:downcase).sort
assert_equal('en', manifest.fetch('main_language'))
assert_equal(languages, embedded.supported_languages.map(&:to_s).sort, 'Manifest language declarations differ')
codes = languages - ['en']
assert_equal(codes.map { |code| "#{code.upcase}.mo" }.sort, Dir.glob('*.mo', base: locale).sort,
  'Runtime catalogs differ from declared languages')
files = Dir.children(locale).sort
assert(files.all? { |name| name.match?(/\A(?:[A-Z]{2}\.(?:po|mo)|game-room\.pot)\z/) },
  "Unexpected locale files: #{files}")
assert(!files.include?('EN.po') && !files.include?('EN.mo'), 'English is the source language')
codes.each { |code| assert(files.include?("#{code.upcase}.po"), "Missing editable catalog: #{code}") }
expected = codes.to_h { |code| [code, File.binread(File.join(locale, "#{code.upcase}.mo"))] }
release = GameRoomReleaseFiles.files(root)
assert_equal(codes.map { |code| "locale/#{code.upcase}.mo" }.sort, release.grep(%r{\Alocale/}),
  'Staging includes translation sources or omits a runtime catalog')

# Build only a disposable fixture with the real catalogs, never a Game Room
# release. Both native builders and the native package reader participate.
scratch = Dir.tmpdir
Dir.mktmpdir('lc', scratch) do |directory|
  assert(File.expand_path(directory).start_with?(File.expand_path(scratch) + '/'), 'Fixture outside temporary parent')
  source = File.join(directory, 'src')
  assert(source.length <= 80, 'Fixture exceeds the Windows builder path limit') if Gem.win_platform?
  FileUtils.mkdir_p(File.join(source, 'locale'))
  files.each { |name| FileUtils.cp(File.join(locale, name), File.join(source, 'locale', name)) }
  metadata = {
    'id' => 'a87895e2-a456-4f5c-b0cb-dcd72885d2c8', 'name' => 'Locale contract fixture', 'author' => 'Test fixture',
    'version' => '0.0.1', 'build_id' => '1', 'platforms' => ['all'],
    'main' => '__app.rb', 'main_class' => 'LocaleContractFixture',
    'EltenAPIVersion' => manifest.fetch('EltenAPIVersion'), 'main_language' => 'en',
    'supported_languages' => languages,
    'localized_descriptions' => manifest.fetch('localized_descriptions')
  }
  app = "=begin Elten3AppInfo\n#{JSON.generate(metadata)}\n=end Elten3AppInfo\nclass LocaleContractFixture; end\n"
  File.binwrite(File.join(source, '__app.rb'), app)
  %w[eltenapp eltsetup].each do |format|
    builder = EltenTestHost.file("tools/build-#{format}.rb")
    target = File.join(directory, "fixture.#{format}")
    output, status = Open3.capture2e(RbConfig.ruby, builder, '--unsigned', source, target)
    assert(status.success?, "Native #{format} build failed: #{output}")
    assert(!output.include?('Warning:'), "Native #{format} metadata warning: #{output}")
    package_path = target
    if format == 'eltsetup'
      Zip::File.open(target) do |zip|
        payload = JSON.parse(zip.read('__manifest.json')).fetch('payload')
        assert_equal(languages, payload.fetch('supported_languages').sort)
        assert_equal(['__manifest.json', payload.fetch('entry')].sort, zip.entries.map(&:name).sort,
          'Translation sources leaked into the installer')
        package_path = File.join(directory, 'from-installer.eltenapp')
        File.binwrite(package_path, zip.read(payload.fetch('entry')))
      end
    end
    begin
      # The host explicitly accepts unsigned development fixtures in this
      # isolated process; production signature verification is unchanged.
      previous_mode = $developer_mode
      $developer_mode = true
      package = Programs::EltenAppPackage.new(package_path)
    ensure
      $developer_mode = previous_mode
    end
    assert_equal(['__app.rb'], package.code_files.keys, 'Builder omitted or added fixture code')
    assert_equal(app.b, package.code_files.fetch('__app.rb').b)
    assert_equal(expected, package.language_files, "#{format}: language IDs or MO bytes changed")
    assert_equal(languages, package.manifest.supported_languages.map(&:to_s).sort)
    assert(package.sound_files.empty? && package.native_files.empty?, 'Unexpected package resources')

    # Use the actual host accessor without registering a program or accessing
    # a profile. Every requested catalog must come from the parsed package.
    runtime = Programs::Runtime.allocate
    runtime.instance_variable_set(:@language_files, package.language_files)
    runtime.instance_variable_set(:@manifest, package.manifest)
    runtime.define_singleton_method(:physical_path) { |*| raise 'Catalog fell back to disk' }
    codes.each do |code|
      assert_equal(expected.fetch(code), runtime.language_data(code.upcase))
      GameRoomLocalization.boot(runtime: runtime, settings: { 'interface_language' => code }, host_language: 'en', known_languages: [])
      assert_equal(languages, GameRoomLocalization.available_languages.map { |row| row.fetch(:id) }.sort)
      assert_equal(code, GameRoomLocalization.primary_language)
      assert_equal('Missing catalog probe', GameRoomLocalization.translate('Missing catalog probe'))
    end
    GameRoomLocalization.boot(runtime: runtime, settings: { 'interface_language' => 'en' }, host_language: 'pl', known_languages: codes)
    assert_equal('Chess', GameRoomLocalization.translate('Chess'), 'Explicit English inherited a translation')
  end
end
puts 'Locale contract: minimal files, matching manifests/staging, native eltenapp/eltsetup builders, exact MO bytes and host language access'
