require_relative "../support/translation_reference"
require "json"

root = File.expand_path("../..", __dir__)
bytes = File.binread(File.join(root, "locale/PL.mo"))
count, originals, translations = bytes.byteslice(8, 12).unpack("V3")
catalog = count.times.to_h do |index|
  length, offset = bytes.byteslice(originals + index * 8, 8).unpack("V2")
  key = bytes.byteslice(offset, length).force_encoding("UTF-8")
  length, offset = bytes.byteslice(translations + index * 8, 8).unpack("V2")
  [key, bytes.byteslice(offset, length).force_encoding("UTF-8")]
end
sources = GameRoomTest::TranslationReference.fetch("table_features")
sources.each do |english, polish|
  raise "Missing compiled translation: #{english}" unless catalog[english] == polish
  raise "Invalid Polish encoding" unless polish.valid_encoding?
  raise "Translation lost placeholders" unless english.scan(/%\{[^}]+\}/).sort == polish.scan(/%\{[^}]+\}/).sort
end
raise "Saved games heading not Polish" unless catalog["Saved games"] == "Zapisane gry"
raise "Transferred master is incorrectly called the table creator" unless catalog["table master"] == "gospodarz stołu"
puts "Table settings, material counters, saved games and invitations: #{sources.length} Polish translations OK"
