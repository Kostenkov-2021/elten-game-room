require_relative '../../lib/game_option_values'

# The same formatter supplies table settings, rules and tournament documents.
# Use the actual compiled catalogs and their plural rules, not a text stub.
directory = File.expand_path('../../locale', __dir__)
definition = Struct.new(:kind, :summary_unit).new(:integer, :seconds)
counts = [0, 1, 2, 4, 5, 11, 12, 21, 22, 101]
suffixes = {
  'en' => %w[seconds second seconds seconds seconds seconds seconds seconds seconds seconds],
  'pl' => %w[sekund sekunda sekundy sekundy sekund sekund sekund sekund sekundy sekund],
  'cs' => Array.new(counts.size, 's'), # Preserve the existing Czech abbreviation.
  'es' => %w[segundos segundo segundos segundos segundos segundos segundos segundos segundos segundos],
  'ru' => %w[секунд секунда секунды секунды секунд секунд секунд секунда секунды секунда]
}
failures = []
suffixes.each do |language, forms|
  GameRoomLocalization.boot(directory: directory, host_language: language,
    settings: {'interface_language' => language, 'known_languages' => []})
  counts.zip(forms).each do |count, word|
    actual = GameRoomOptionValues.format(definition, count)
    expected = "#{count} #{word}"
    failures << [language, count, expected, actual] unless actual == expected && actual.encoding == Encoding::UTF_8
  end
  plain = Struct.new(:kind, :summary_unit).new(:integer, nil)
  raise 'Integer without a time unit was changed' unless GameRoomOptionValues.format(plain, 1) == '1'
end
raise "Time-unit plural failures: #{failures.inspect}" unless failures.empty?
puts 'PASS shared option seconds: actual EN/PL/CS/ES/RU catalogs, 50 plural forms and unchanged plain integers'
