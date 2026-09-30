require 'gettext/mo'
require_relative "../../tools/support/translation_extractor"
require_relative "../../content/monopoly_regional_data"
root = File.expand_path("../..", __dir__)
catalog = GetText::MO.open(File.join(root, 'locale/PL.mo')).to_h.transform_keys { |key| key.dup.force_encoding('UTF-8') }
scopes = %r{\A(?:games/(?:uno|poker|makao|yahtzee|monopoly)(?:\.rb|/)|games/generated/rulebooks/(?:uno|poker|makao|yahtzee|monopoly)\.rb|content/monopoly_boards\.rb|lib/game_surfaces/(?:roll_and_score|packet_cards)\.rb|lib/game_screen(?:\.rb|/))}
strings = GameRoomTranslationExtractor.extract(root, warnings: []).filter_map do |message|
  next unless message.fetch(:references).any? { |reference| reference.match?(scopes) }
  key = message.fetch(:msgid)
  key = "#{message[:msgctxt]}\u0004#{key}" if message[:msgctxt]
  key += "\0#{message[:msgid_plural]}" if message[:msgid_plural]
  key
end
# Street/city names are proper names; generic transport/company/neutral
# squares also need catalogue coverage even though their labels are data.
strings += GameRoomContent::MonopolyRegionalData::PROFILES.values.flat_map do |profile|
  profile[:layout].filter_map { |type, name, _group| name if [:railroad, :utility, :neutral].include?(type) }
end
strings.uniq!
missing = strings.reject { |value| catalog.key?(value) && !catalog[value].empty? }
raise "Missing Polish translations:\n#{missing.join("\n")}" unless missing.empty?
puts "PASS core card-game and Monopoly translations: #{strings.length} messages, including extracted modules/rules"
