require "optparse"
require "json"

ENV["BUNDLE_GEMFILE"] = File.expand_path("Gemfile.i18n", __dir__)
begin
  require "bundler/setup"
rescue LoadError, StandardError => error
  warn "Install translation tools with: bundle install --gemfile tools/Gemfile.i18n"
  warn error.message
  exit 1
end

require_relative "support/translation_catalog"
require_relative "support/translation_extractor"
require_relative "support/translation_documents"

module GameRoomTranslationCLI
  module_function

  def language_code(value)
    code = value.to_s
    raise ArgumentError, "Use a two-letter language code, such as PL or CS" unless code.match?(/\A[a-z]{2}\z/i)
    raise ArgumentError, "English is the source language; edit English source text, not EN.po" if code.casecmp?("en")
    code.upcase
  end

  def catalog_codes(directory, extension)
    Dir.glob("*.#{extension}", base: directory).sort.map { |name| File.basename(name, ".#{extension}") }
  end

  def run(arguments)
    options = { root: File.expand_path("..", __dir__), check: false }
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: ruby tools/translations.rb [--root PROJECT] import-mo|update|new|compile|check [LANGUAGE] [--name NATIVE_NAME]"
      opts.on("--root PATH") { |path| options[:root] = File.expand_path(path) }
      opts.on("--name NAME") { |name| options[:name] = name }
      opts.on("--plural-forms RULE") { |rule| options[:plural_forms] = rule }
      opts.on("--check") { options[:check] = true }
    end
    parser.parse!(arguments)
    command = arguments.shift
    if options[:check] && !%w[compile check].include?(command)
      raise ArgumentError, "--check is supported only for compile; no files were changed"
    end
    root = options.fetch(:root)
    directory = File.join(root, "locale")
    raise ArgumentError, "Missing locale directory: #{directory}" unless File.directory?(directory)
    case command
    when "import-mo"
      codes = arguments.empty? ? catalog_codes(directory, "mo") : arguments
      raise ArgumentError, "No MO catalogs to import" if codes.empty?
      codes.map { |code| language_code(code) }.each do |code|
        target = File.join(directory, "#{code}.po")
        raise ArgumentError, "Refusing to overwrite #{target}" if File.exist?(target)
        catalog = GameRoomTranslationCatalog.from_mo(File.join(directory, "#{code}.mo"))
        GameRoomTranslationCatalog.write_po(catalog, target)
        puts "Imported #{code}.mo into the editable #{code}.po"
      end
    when "update"
      raise ArgumentError, "update does not accept language arguments" unless arguments.empty?
      paths = catalog_codes(directory, "po").map { |code| File.join(directory, "#{code}.po") }
      raise ArgumentError, "Import the existing MO catalog first" if paths.empty?
      messages = GameRoomTranslationExtractor.extract(root)
      catalogs = paths.map { |path| [path, GameRoomTranslationCatalog.read_po(path)] }
      catalogs.each { |_path, catalog| GameRoomTranslationCatalog.add_messages(catalog, messages) }
      master = catalogs.find { |path, _catalog| File.basename(path) == "PL.po" } || catalogs.first
      template = GameRoomTranslationCatalog.template(master.last)
      catalogs.each { |path, catalog| GameRoomTranslationCatalog.write_po(catalog, path) }
      GameRoomTranslationCatalog.write_po(template, File.join(directory, "game-room.pot"))
      puts "Updated #{catalogs.length} PO catalog(s) and game-room.pot from #{messages.length} source messages; existing translations retained"
    when "new"
      raise ArgumentError, "new requires exactly one language code" unless arguments.length == 1
      code = language_code(arguments.first)
      path = File.join(directory, "#{code}.po")
      raise ArgumentError, "Refusing to overwrite #{path}" if File.exist?(path)
      template = GameRoomTranslationCatalog.read_po(File.join(directory, "game-room.pot"))
      defaults = JSON.parse(File.read(File.join(__dir__, "plural_forms.json"), encoding: "UTF-8")).fetch("plural_forms")
      forms = options[:plural_forms] || defaults[code.downcase]
      catalog = GameRoomTranslationCatalog.new_catalog(template, language: code.downcase, native_name: options[:name] || code, plural_forms: forms)
      GameRoomTranslationCatalog.write_po(catalog, path)
      puts "Created #{code}.po; no MO was built or installed"
    when "compile", "check"
      check = command == "check" || options[:check]
      codes = arguments.empty? ? catalog_codes(directory, "po") : arguments
      raise ArgumentError, "No PO catalogs to compile" if codes.empty?
      codes = codes.map { |code| language_code(code) }.uniq
      codes.each do |code|
        input = File.join(directory, "#{code}.po")
        GameRoomTranslationCatalog.compile_file(input, File.join(directory, "#{code}.mo"), check: check)
        puts "#{check ? 'Verified' : 'Compiled'} #{code}.po -> #{code}.mo"
      end
      if codes.include?("PL")
        catalog = GameRoomTranslationCatalog.read_po(File.join(directory, "PL.po"))
        messages = GameRoomTranslationCatalog.message_map(catalog)
        documents = GameRoomTranslationDocuments.sync(root, messages, check: check)
        puts "#{check ? 'Verified' : 'Refreshed'} Polish rulebooks (#{documents.length} changed)"
      end
    else
      raise ArgumentError, parser.to_s
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    GameRoomTranslationCLI.run(ARGV)
  rescue StandardError => error
    warn "Translation operation failed: #{error.message}"
    exit 1
  end
end
