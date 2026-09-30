require_relative "../support/translation_reference"
require "json"

root = File.expand_path("../..", __dir__)
mo = File.binread(File.join(root, "locale/PL.mo"))
count, originals, translations = mo.byteslice(8, 12).unpack("V3")
catalog = count.times.to_h do |index|
  size, offset = mo.byteslice(originals + index * 8, 8).unpack("V2")
  source = mo.byteslice(offset, size).force_encoding("UTF-8")
  size, offset = mo.byteslice(translations + index * 8, 8).unpack("V2")
  [source, mo.byteslice(offset, size).force_encoding("UTF-8")]
end
additions = GameRoomTest::TranslationReference.fetch("game_messages")
additions.each do |source, translation|
  raise "Uncompiled message: #{source}" unless catalog[source] == translation
  variants = translation.split("\0", -1)
  raise "Wrong Polish plural forms: #{source}" if source.include?("\0") && variants.length != 3
  placeholders = source.split("\0").first.scan(/%\{[^}]+\}/).sort
  variants.each do |variant|
    raise "Missing translation: #{source}" if variant.empty?
    raise "Message placeholder lost: #{source}" unless variant.scan(/%\{[^}]+\}/).sort == placeholders
  end
end
raise "Too-late penalty is still spoken" unless catalog.fetch("Too late!") == "Za późno!"
raise "Raise prompt is not concise" unless catalog.fetch("Raise by:") == "Podbij o:"
raise "High-card-only G message is wrong" unless catalog.fetch("You have no combination.") == "Nie masz układu"
puts "#{additions.length} compiled Polish messages, plural forms and placeholders passed"
