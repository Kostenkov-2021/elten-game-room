require_relative "../support/translation_reference"
require_relative "../support/binary_rule_dictionary"
class DictionaryPingWorker
  def busy?; false; end
  def start(&block); @result = [block.call, nil]; true; end
  def take; result, @result = @result, nil; result; end
end
translations = GameRoomTest::TranslationReference.fetch("room_feedback")
%w[pl en fallback].each do |language|
  $rules_english = language != 'pl'
  GameRoomTestLocalization.use_language(language)
  translations.each do |source, translated|
    actual = GameRoomLocalization.translate(source.b)
    expected = language == 'pl' ? translated : source
    raise "New shortcut translation missing: #{source}" unless actual == expected
    raise 'Binary help encoding' unless (actual + ' — żółty').valid_encoding?
  end
  ping_owner = Object.new
  ping = GameRoomPing.new(ping_owner, worker: DictionaryPingWorker.new, clock: -> { 0.0 }, probe: -> { true })
  relay = Object.new
  relay.define_singleton_method(:ping_sample) { {relay_udp_ms: 17} }
  ping.communications_channel = relay
  ping.request(ping_owner)
  expected_ping = language == 'pl' ? 'HTTP: 0 ms. Communications UDP, serwer pośredniczący: 17 ms.' :
    'HTTP ping: 0 ms. Communications UDP relay ping: 17 ms.'
  actual_ping = ping.poll(ping_owner)
  raise 'Binary ping interpolation or translation failed' unless actual_ping == expected_ping && (actual_ping + ' — żółty').valid_encoding?
  assignment = GameRoomTeams::Assignment.new(players: ['Łukasz', 'Żaneta', GameRoomParticipants.bot_id(1, 1, name_token: 'pl20'), 'Bob'], team_size: 2)
  list = GameRoomScreens::TeamList.new(assignment)
  raise 'Binary team heading' unless (list.header + ' — wybór').valid_encoding?
  raise 'Lost team/bot names' unless list.options[2].include?('Maślana')
  list.get_tips.each { |tip| raise 'Invalid team hint encoding' unless (tip + ' — skrót').valid_encoding? }
  macros = GameRoomScreens::TablePresetList.new([], editor: ->(*) {}, writer: ->(*) {})
  raise 'Missing 30 slots' unless macros.options.length == 30 && macros.options.last.start_with?('Shift+0:')
  macros.options.each { |label| raise 'Binary macro label' unless (label + ' — opcja').valid_encoding? }
end
puts 'PASS new ping, macros and team labels: binary-loaded sources, native dictionary PL/EN/fallback'
