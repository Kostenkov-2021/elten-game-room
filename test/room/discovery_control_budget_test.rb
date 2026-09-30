require_relative "../support/native_live_sessions"
require_relative "../../games/makao"

broker = NativeLiveSessionsBroker.new
$game_room_test_user = 'Alice'
transport = GameRoomTransport.new(ProgramDouble.new(broker.endpoint('Alice')))
options = JSON.generate(GameRoomGames::Makao.new.default_options)
table = transport.create_room(name: 'Custom table', game: 'makao', owner: 'Alice', game_options: options)
store = transport.instance_variable_get(:@live_store)
metadata = broker.cores.values.first.discovery_metadata
metadata = metadata.merge('control_anchor' => {'seq'=>12345, 'digest'=>'a'*64})
compact = store.send(:compact_discovery, metadata)
assert(JSON.generate(compact).bytesize <= 1024, 'Control anchor exceeds native discovery budget')
assert(store.send(:discovery_options, compact) == options, 'Custom options were lost')
options = JSON.generate((1..60).to_h { |i| ["option_#{i}", 'custom value'] })
compact = store.send(:compact_discovery, metadata.merge('game_options'=>options))
assert(compact.key?('options_z') && JSON.generate(compact).bytesize <= 1024, 'Large profile is not compacted')
assert(store.send(:discovery_options, compact) == options, 'Compressed profile changed')
%w[bad].each do |bad|
  begin
    store.send(:discovery_options, {'options_z'=>bad})
    raise 'Malformed options accepted'
  rescue ArgumentError
  end
end
[Zlib::Deflate.deflate('x'*100000), Zlib::Deflate.deflate('{}')+'junk', Zlib::Deflate.deflate('{}')[0...-1]].each do |bad|
  begin
    store.send(:discovery_options, {'options_z'=>Base64.strict_encode64(bad)})
    raise 'Invalid compressed options accepted'
  rescue ArgumentError, Zlib::Error
  end
end
puts 'Discovery control budget: OK'
