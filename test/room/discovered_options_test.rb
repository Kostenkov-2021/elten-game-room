require_relative '../support/native_live_sessions'
broker = NativeLiveSessionsBroker.new
$game_room_test_user = 'Alice'
owner = GameRoomTransport.new(ProgramDouble.new(broker.endpoint('Alice')))
reader = GameRoomTransport.new(ProgramDouble.new(broker.endpoint('Bob')))
options = JSON.generate('variant' => 'teams', 'score_limit' => 1000)
room = owner.create_room(name: 'Options fixture', game: 'tysiac', owner: 'Alice', game_options: options, capacity: 4, private_table: false)
store = owner.instance_variable_get(:@live_store)
store.publish_discovery(room['__id'])
row = reader.discover_rooms.first
assert(reader.discovered_options(row) == {status: :ready, game: 'tysiac', options: options}, 'wrong discovered options')
assert(broker.endpoint('Bob').sessions.empty?, 'option read joined table')
core = broker.cores.values.first
metadata = core.discovery_metadata.dup
core.discovery_metadata = metadata.merge('game_options' => '{"variant":"four_players"}')
assert(JSON.parse(reader.discovered_options(row)[:options])['variant'] == 'four_players', 'options stayed stale')
['', 'bad json', '[]', 'null'].each do |invalid|
  core.discovery_metadata = metadata.merge('game_options' => invalid)
  assert(reader.discovered_options(row)[:status] == :unavailable, 'invalid options became defaults')
end
core.discovery_metadata = metadata.merge('options_z' => 'broken base64')
assert(reader.discovered_options(row)[:status] == :unavailable, 'invalid compression was accepted')
core.discovery_metadata = metadata
owner.deactivate_table(table_id: room['__id'])
assert(reader.discovered_options(row)[:status] == :closed, 'closed table settings still announced')
assert(broker.endpoint('Bob').sessions.empty?, 'closed read joined table')
puts 'PASS discovery options: refreshed values, no membership, malformed plain/compressed data, closed table'
