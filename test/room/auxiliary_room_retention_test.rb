require_relative "../support/native_live_sessions"

$game_room_test_user = 'Alice'
broker = NativeLiveSessionsBroker.new
program = ProgramDouble.new(broker.endpoint('Alice'))
transport = GameRoomTransport.new(program)
repository = GameRepository.new(program, transport: transport)
reader = GameRoomTransport.new(ProgramDouble.new(broker.endpoint('Reader')))
guest = GameRoomTransport.new(ProgramDouble.new(broker.endpoint('Bob')))
create = ->(name) { transport.create_room(name: name, game: 'test', owner: 'Alice', game_options: '{}', capacity: 8) }
active = create.call('Active retained')
active_controller = repository.bot_turn_controller(active['__id'])
subscribed = create.call('Subscribed retained')
feed = transport.subscribe_game_session(subscribed['__id'])
transport.deactivate_table(table_id: subscribed['__id'])
pending = create.call('Pending controller')
pending_controller = repository.bot_turn_controller(pending['__id'])
lease = pending_controller.acquire(session_id: 123, actor: 'Alice', revision: [0, 0])
pending_controller.submission_failed(lease)
transport.deactivate_table(table_id: pending['__id'])
last = nil
25.times do |index|
  room = create.call("Retention #{index}")
  id = room.fetch('__id')
  assert(guest.establish_membership_status(table_id: id, owner: 'Alice', capacity: 8, user: 'Bob', table: room) == :joined, 'guest join failed')
  game = transport.start_game(table: room, game: 'test', players: %w[Alice Bob], options: '{}', actor: 'Alice')
  transport.append_game_action(session: game, sequence: 0, events: [{'action' => 'play', 'value' => ''}], actor: 'Alice')
  repository.bot_turn_controller(id)
  reader.discover_rooms
  transport.deactivate_table(table_id: id)
  last = id
end
reader.discover_rooms
repository.bot_turn_controller(last)
store = transport.instance_variable_get(:@live_store)
failures = []
cached = reader.instance_variable_get(:@live_store).instance_variable_get(:@discovered)
failures << 'discovery retained disappeared rooms' unless cached.keys == [active['__id']]
%w[pending_table_changes pending_game_changes pending_game_starts pending_recoveries newly_joined].each do |name|
  [transport, guest].each do |client|
    size = client.instance_variable_get("@#{name}").length
    failures << "#{name} unbounded: #{size}" if size > 10
  end
end
failures << 'idle controller map unbounded' if repository.instance_variable_get(:@bot_turn_controllers).length > 11
failures << 'subscribed room source discarded' unless store.instance_variable_get(:@rooms).key?(subscribed['__id'])
assert(repository.bot_turn_controller(active['__id']).equal?(active_controller), 'active controller replaced')
assert(repository.bot_turn_controller(pending['__id']).equal?(pending_controller), 'unconfirmed controller replaced')
assert(feed.consume_recovery(subscribed['__id']) == :closed, 'live feed lost terminal notification')
assert(transport.consume_recovery(last) == :closed, 'recent inactive room lost terminal notification')
puts JSON.generate(discovery: cached.length, controllers: repository.instance_variable_get(:@bot_turn_controllers).length,
  queues: %w[pending_table_changes pending_game_changes pending_game_starts pending_recoveries newly_joined].to_h { |name| [name, [transport, guest].map { |client| client.instance_variable_get("@#{name}").length }] })
feed.close
raise failures.join('; ') unless failures.empty?
puts 'Auxiliary retention: disappeared discovery, queues, idle controllers; active, unconfirmed and subscribed state retained OK'
