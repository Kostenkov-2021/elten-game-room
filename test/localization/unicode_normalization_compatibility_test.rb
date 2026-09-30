# encoding: UTF-8
require "json"

ROOT = File.expand_path("../..", __dir__)

def assert(condition, message)
  raise message unless condition
end

def assert_raises(type, message)
  begin
    yield
  rescue type
    return
  end
  raise message
end

# Evaluate binary sources in an application namespace, as ELTEN does. A local
# Encoding facade models hosts without UNICODE_VERSION or with older tables;
# never add, remove or replace constants on the real host's Encoding class.
def load_content(host_version)
  application = Module.new
  encoding = Class.new
  Encoding.constants(false).each do |name|
    next if name == :UNICODE_VERSION
    encoding.const_set(name, Encoding.const_get(name, false))
  end
  encoding.const_set(:UNICODE_VERSION, host_version) unless host_version == :missing
  application.const_set(:Encoding, encoding)
  loaded = {}
  loading = []
  loader = lambda do |path|
    path = File.expand_path(path)
    next false if loaded[path]
    loading << path
    begin
      application.module_eval(File.binread(path), path, 1)
      loaded[path] = true
    ensure
      loading.pop
    end
    true
  end
  application.define_singleton_method(:require_relative) do |name|
    file = name.end_with?(".rb") ? name : name + ".rb"
    loader.call(File.expand_path(file, File.dirname(loading.last)))
  end
  loader.call(File.join(ROOT, "lib/game_content.rb"))
  [application, encoding, loaded]
end

host_constants = Encoding.constants(false).sort
host_version = Encoding.const_get(:UNICODE_VERSION, false) if host_constants.include?(:UNICODE_VERSION)
host_normalizer = Object.const_get(:UnicodeNormalize, false) if Object.const_defined?(:UnicodeNormalize, false)

samples = [
  ["ASCII 123", :nfc, "ASCII 123"],
  ["", :nfc, ""],
  ["Za\u007A\u0307o\u0301\u0142c\u0301 ge\u0328s\u0301la\u0328", :nfc, "Zażółć gęślą"],
  ["a\u0315\u0300b\u0315\u0300", :nfc, "à\u0315b\u0300\u0315"],
  ["\u0315\u0300a\u0315\u0300", :nfd, "\u0300\u0315a\u0300\u0315"],
  ["a\u0301\u0300", :nfc, "á\u0300"],
  ["\u1E0A\u0323", :nfc, "\u1E0C\u0307"],
  ["\u212B", :nfc, "Å"],
  ["Ą", :nfd, "A\u0328"],
  ["\u1100\u1161\u11A8", :nfc, "\uAC01"],
  ["\uAC01", :nfd, "\u1100\u1161\u11A8"],
  ["\uFF21\u2460\uFB01", :nfkc, "A1fi"],
  ["\uFF21\u2460\uFB01", :nfkd, "A1fi"],
  # Todhri was added after Unicode 15. These mappings must come from our
  # bundled tables, not from the host's Unicode character properties.
  ["\u{105D2}\u0307", :nfc, "\u{105C9}"],
  ["\u{105C9}", :nfd, "\u{105D2}\u0307"]
]

# Optional complete Unicode conformance corpus. Keep downloaded test data out
# of the player installer; the ordinary regression is self-contained.
conformance_cases = []
if ARGV.first
  require "digest"
  corpus = File.binread(ARGV.first)
  expected_sha256 = "5019ffd530751a741900c849c0e010332f142a3612234639bd200b82138a87db"
  assert(Digest::SHA256.hexdigest(corpus) == expected_sha256, "unexpected Unicode 17 conformance data")
  corpus.each_line do |line|
    values = line.split("#", 2).first.to_s.strip
    next if values.empty? || values.start_with?("@")
    columns = values.split(";").first(5).map { |column| column.split.map { |codepoint| codepoint.to_i(16) }.pack("U*") }
    assert(columns.length == 5, "invalid normalization test row")
    conformance_cases << columns
  end
  assert(conformance_cases.length > 20_000, "incomplete Unicode conformance corpus")
end

[:missing, "15.0.0", "17.0.0"].each do |version|
  application, encoding, loaded = load_content(version)
  normalizer = application.const_get(:UnicodeNormalize, false)
  content = application.const_get(:GameRoomContent, false)
  assert(loaded.length == 3, "normalization did not load all three bundled sources")
  assert(normalizer::TABLE_UNICODE_VERSION == "17.0.0", "bundled table version is not pinned")

  samples.each do |input, form, expected|
    original = input.dup
    actual = normalizer.normalize(input, form)
    assert(actual == expected, "#{version}: #{form} mismatch for #{input.inspect}: #{actual.inspect}")
    assert(normalizer.normalize(actual, form) == actual, "#{version}: #{form} was not idempotent")
    assert(normalizer.normalized?(actual, form), "#{version}: normalized text was not recognized")
    assert(input == original, "normalization modified its input")
  end
  assert(!normalizer.normalized?("a\u0328", :nfc), "a decomposed Polish letter was already normalized")
  [Encoding::UTF_16LE, Encoding::UTF_16BE, Encoding::UTF_32LE, Encoding::UTF_32BE].each do |encoding_type|
    result = normalizer.normalize("a\u0328".encode(encoding_type))
    assert(result.encoding == encoding_type && result.encode(Encoding::UTF_8) == "ą", "UTF transcoding lost NFC")
  end
  assert_raises(ArgumentError, "invalid normalization form was accepted") { normalizer.normalize("a", :invalid) }
  assert_raises(Encoding::CompatibilityError, "raw binary normalization was silently accepted") { normalizer.normalize("a".b) }
  assert_raises(ArgumentError, "invalid UTF-8 was silently accepted") { normalizer.normalize("\xFF".force_encoding(Encoding::UTF_8)) }

  polish = content::LanguageProfile.new(
    id: "pl-PL", label: "Polski".b,
    alphabet: %w[a ą b c ć d e ę f g h i j k l ł m n ń o ó p r s ś t u w y z ź ż],
    normalizer: ->(text) { text.downcase }
  )
  decomposed = "  ZA\u005A\u0307O\u0301\u0141C\u0301   GE\u0328S\u0301LA\u0328  ".b
  result = polish.normalize(decomposed)
  assert(result == "zażółć gęślą" && result.encoding == Encoding::UTF_8, "binary Polish text lost normalization")
  assert(polish.valid_word_shape?("a\u0328".b), "decomposed Polish letters were rejected as words")
  assert(polish.graphemes("a\u0328c\u0301".b) == ["ą", "ć"], "grapheme splitting bypassed NFC")
  assert_raises(ArgumentError, "canonically duplicate alphabet letters were accepted") do
    content::LanguageProfile.new(id: "pl", label: "Polish", alphabet: ["ą", "a\u0328"])
  end
  assert(encoding.const_defined?(:UNICODE_VERSION, false) == (version != :missing), "normalizer patched host Encoding")
  assert(encoding.const_get(:UNICODE_VERSION, false) == version, "normalizer changed host Unicode version") unless version == :missing

  targets = { nfc: [1, 1, 1, 3, 3], nfd: [2, 2, 2, 4, 4], nfkc: [3, 3, 3, 3, 3], nfkd: [4, 4, 4, 4, 4] }
  conformance_cases.each_with_index do |columns, index|
    targets.each do |form, expected_columns|
      columns.each_with_index do |input, column|
        expected = columns.fetch(expected_columns.fetch(column))
        assert(normalizer.normalize(input, form) == expected, "#{version}: Unicode case #{index + 1}, #{form}, column #{column + 1}")
        assert(normalizer.normalized?(input, form) == (input == expected), "#{version}: Unicode normalized? case #{index + 1}, #{form}, column #{column + 1}")
      end
    end
  end
end

assert(Encoding.constants(false).sort == host_constants, "test changed real host constants")
assert(Encoding.const_get(:UNICODE_VERSION, false) == host_version, "test changed real host Unicode version") if host_version
actual_host_normalizer = Object.const_get(:UnicodeNormalize, false) if Object.const_defined?(:UnicodeNormalize, false)
assert(actual_host_normalizer.equal?(host_normalizer), "bundled normalizer escaped the application namespace")
puts "PASS Unicode normalization compatibility: Ruby #{RUBY_VERSION}, three host versions, binary sources, NFC/NFD/NFKC/NFKD and Polish content"
puts "PASS all #{conformance_cases.length} published Unicode 17 rows across three host versions (#{conformance_cases.length * 120} conformance assertions)" unless conformance_cases.empty?
