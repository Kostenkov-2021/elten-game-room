require_relative 'support/binary_rule_dictionary'

source = Object.new
sample = {relay_udp_ms: 15, peers: [{user: 'Łukasz'.b, transport: :p2p, p2p_ms: 24},
  {user: 'Żaneta'.b, transport: :relay}]}
source.define_singleton_method(:ping_sample) { sample }
ping = GameRoomPing.new(Object.new, worker: Object.new)
ping.communications_channel = source
%w[pl en fallback].each do |language|
  $rules_english = language != 'pl'
  GameRoomTestLocalization.use_language(language)
  expected = if language == 'pl'
    'Communications: połączenia mieszane, P2P i przez serwer pośredniczący. P2P z Łukasz: 24 ms. Communications przez serwer pośredniczący: Żaneta. Communications UDP, serwer pośredniczący: 15 ms.'
  else
    'Communications: mixed P2P and relay connections. P2P with Łukasz: 24 ms. Communications via relay: Żaneta. Communications UDP relay ping: 15 ms.'
  end
  text = ping.send(:communications_announcement)
  raise "Wrong #{language} ping translation" unless text == expected && (text + ' — żółty').valid_encoding?
  sample[:peers][0][:p2p_ms] = nil
  unavailable = ping.send(:communications_announcement)
  expected_unavailable = language == 'pl' ? 'P2P z Łukasz: ping niedostępny.' : 'P2P with Łukasz: ping is unavailable.'
  raise 'Missing direct RTT translation/encoding' unless unavailable.include?(expected_unavailable)
  sample[:peers][0][:p2p_ms] = 24
end
puts 'PASS P2P ping: binary sources, PL/EN/fallback, Unicode participants and missing RTT'
