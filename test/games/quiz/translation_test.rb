require_relative "../../support/translation_reference"
# encoding: UTF-8
require "json"
require_relative "../../../lib/game_room_localization"
root = File.expand_path("../../..", __dir__)
mo = File.binread(File.join(root, "locale/PL.mo"))
count, originals, translations = mo.byteslice(8, 12).unpack("V3")
catalog = count.times.to_h do |i|
  len, off = mo.byteslice(originals + 8*i, 8).unpack("V2")
  key = mo.byteslice(off, len).force_encoding("UTF-8")
  len, off = mo.byteslice(translations + 8*i, 8).unpack("V2")
  [key, mo.byteslice(off, len).force_encoding("UTF-8")]
end
compiled = GameRoomLocalization::Catalog.new(mo)
lookup = ->(source) { catalog[source] || (!source.include?("\0") ? compiled.translate(source) : nil) }
strings = File.read(File.join(root, "games/quiz_party.rb"), encoding: "UTF-8").scan(/\b_\("([^"\\]*(?:\\.[^"\\]*)*)"\)/).flatten
strings += ["General knowledge", "%{count} question", "%{count} questions"]
strings += ["Choose a category.", "%{player} is choosing a category."]
strings += ["Your answer could not be saved on this device and was not sent. Please try again."]
missing = strings.uniq.reject { |text| lookup.call(text) && !lookup.call(text).empty? }
raise "Missing Quiz translations: #{missing.inspect}" unless missing.empty?
GameRoomTest::TranslationReference.fetch("quiz").each do |english, polish|
  raise "Uncompiled translation: #{english}" unless lookup.call(english) == polish
  english.split("\0").each do |form|
    polish.split("\0").each do |translated|
      raise "Lost placeholders in #{english}" unless form.scan(/%\{[^}]+\}/).sort == translated.scan(/%\{[^}]+\}/).sort
    end
  end
end
raise "Missing Polish plural forms" unless catalog.fetch("%{count} question\0%{count} questions").split("\0").length == 3
puts "Quiz Polish messages, rules, settings, placeholders and plural forms passed"
