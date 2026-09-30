require "json"

path = File.expand_path("../../lib/game_room_localization.rb", __dir__)
raise "Game Room has no independent interface translator" unless File.file?(path)
require path

def assert(condition, message)
  raise message unless condition
end

polish = GameRoomLocalization::Catalog.new(File.binread(File.expand_path("../../locale/PL.mo", __dir__)))
translator = GameRoomLocalization::Translator.new(catalogs: { "pl" => polish }, primary: "en", known: ["pl"])
assert(translator.translate("Chess") == "Chess", "English Game Room inherited the Polish interface")
translator = GameRoomLocalization::Translator.new(catalogs: { "pl" => polish }, primary: "pl", known: ["en"])
assert(translator.translate("Chess") == "Szachy", "Polish Game Room needs a Polish ELTEN interface")
assert(translator.translate("A missing Game Room translation") == "A missing Game Room translation", "an untranslated message disappeared")
assert(translator.translate("Chess").encoding == Encoding::UTF_8, "translated labels are not UTF-8")
puts "Independent English and Polish Game Room catalogs passed"

def catalog(entries, plural: "nplurals=2; plural=(n != 1);", name: nil)
  messages = { "" => "Content-Type: text/plain; charset=UTF-8\nPlural-Forms: #{plural}\nX-Language-Name: #{name}\n" }.merge(entries).sort
  offset = 28 + messages.length * 16
  blob = "".b
  tables = [messages.map(&:first), messages.map(&:last)].map do |strings|
    strings.map do |string|
      entry = [string.bytesize, offset + blob.bytesize].pack("V2")
      blob << string.b << "\0"
      entry
    end.join
  end
  GameRoomLocalization::Catalog.new([0x950412de, 0, messages.length, 28, 28 + messages.length * 8, 0, 0].pack("V7") + tables.join + blob)
end

czech = catalog({ "Only in Czech" => "Pouze česky", "Same text" => "Same text", "roll\u0004Roll" => "Hodit", "coin\0coins" => "mince\0mince\0mincí" },
  plural: "nplurals=3; plural=(n == 1) ? 0 : (n >= 2 && n <= 4) ? 1 : 2;", name: "Čeština")
other = catalog({ "Only in Czech" => "Do not use an unknown language" })
translator = GameRoomLocalization::Translator.new(catalogs: { "pl" => polish, "cs" => czech, "xx" => other }, primary: "pl", known: ["cs", "en"])
assert(translator.translate("Only in Czech") == "Pouze česky", "a missing primary translation did not use a known language")
assert(translator.translate("Chess") == "Szachy", "a fallback replaced an available primary translation")
assert(translator.translate("Roll", context: "roll") == "Hodit", "context translations did not use the known-language chain")
assert(translator.translate("Only in Czech", context: "unrelated") == "Only in Czech", "a different context leaked into the message")
[1, 2, 4, 5, 12, 21].each do |count|
  expected = count <= 4 ? "mince" : "mincí"
  assert(translator.translate("coin", plural: "coins", count: count) == expected, "Czech plural selection failed for #{count}")
end
unknown = GameRoomLocalization::Translator.new(catalogs: { "cs" => czech }, primary: "pl", known: [])
assert(unknown.translate("Only in Czech") == "Only in Czech", "a language the player does not know was selected")
assert(unknown.translate("coin", plural: "coins", count: 2) == "coins", "English plural fallback was lost")
assert(czech.metadata["X-Language-Name"] == "Čeština", "catalog language names require a host translation")
english_known = GameRoomLocalization::Translator.new(catalogs: { "pl" => polish, "cs" => czech }, primary: "cs", known: %w[cs en pl])
assert(english_known.translate("Chess") == "Szachy", "source English stopped fallback before another known translation")
puts "Known-language fallback, contexts and Czech plurals passed"

runtime = Object.new
runtime.define_singleton_method(:read_json) do |path, default:|
  raise "unexpected settings path" unless path == "settings.json"
  @reads = @reads.to_i + 1
  { "interface_language" => "pl", "known_languages" => ["pl", "en"] }
end
runtime.define_singleton_method(:language_files) { { "pl" => true } }
runtime.define_singleton_method(:manifest) { Struct.new(:supported_languages).new([:en, :pl]) }
runtime.define_singleton_method(:language_data) do |code|
  @catalog_reads = @catalog_reads.to_i + 1
  File.binread(File.expand_path("../../locale/PL.mo", __dir__)) if code == "pl"
end
GameRoomLocalization.boot(runtime: runtime, host_language: "en-GB", known_languages: ["en"])
assert(GameRoomLocalization.translate("Chess") == "Szachy", "persisted Polish UI did not override English host at startup")
assert(GameRoomLocalization.primary_language == "pl", "effective interface language was not exposed")
assert(GameRoomLocalization.available_languages.map { |language| language.fetch(:id) } == %w[en pl], "language options depend on host translations")
100.times { GameRoomLocalization.translate("Chess") }
assert(runtime.instance_variable_get(:@reads) == 1, "UI translation rereads preferences")
assert(runtime.instance_variable_get(:@catalog_reads) == 1, "UI translation rereads catalogs")
normalized = GameRoomLocalization.normalize_settings({ "interface_language" => "en", "known_languages" => ["pl", "pl", "xx"] })
assert(normalized == { "interface_language" => "en", "known_languages" => %w[en pl] }, "language preferences are not normalized or lose the primary language")
GameRoomLocalization.boot(runtime: runtime, host_language: "pl-PL", settings: { "interface_language" => "en" })
assert(GameRoomLocalization.translate("Chess") == "Chess", "persisted English UI did not override Polish host at restart")
puts "Runtime startup, preference normalization and catalog caching passed"

class LocalizationTestBackend
  def evaluate(namespace, code)
    namespace.module_eval(code)
  end
end
namespace = Module.new
namespace.const_set(:GameRoomLocalization, GameRoomLocalization)
LocalizationTestBackend.new.evaluate(namespace, <<~RUBY)
  module ExampleGame
    using GameRoomLocalization::Translations
    NAME = _("Chess")
    def self.name; _("Chess"); end
    class Screen
      def label; _("Chess"); end
      def later; -> { _("Chess") }; end
      def count; n_("coin", "coins", 2); end
    end
  end
RUBY
screen = namespace::ExampleGame::Screen.new
assert(namespace::ExampleGame::NAME == "Chess" && screen.label == "Chess", "local translations missed static or instance labels")
assert(namespace::ExampleGame.name == "Chess" && screen.later.call == "Chess", "local translations missed class methods or callbacks")
assert(screen.count == "coins", "the plural helper lost English fallback")
GameRoomLocalization.boot(settings: { "interface_language" => "pl" })
assert(screen.label == "Szachy", "the refinement uses the global host dictionary")
assert(!Object.new.respond_to?(:_, true), "Game Room changed host translation methods")
puts "Lexically scoped instance/class/constants/callback translation passed"

require_relative "../../lib/bot_names"
assert(GameRoomBotNames.interface_language == "pl", "new computer names still follow ELTEN rather than Game Room")
GameRoomLocalization.boot(settings: { "interface_language" => "en" }, host_language: "pl-PL")
assert(GameRoomBotNames.interface_language == "en", "English Game Room still creates Polish computer names")
puts "Computer-name language follows Game Room without changing stored identities"
