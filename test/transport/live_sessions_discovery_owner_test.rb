require_relative "../support/native_live_sessions"

[:public, :private].each do |visibility|
  broker = NativeLiveSessionsBroker.new
  owner = GameRoomTransport.new(ProgramDouble.new(broker.endpoint('Alice')))
  widget_endpoint = broker.endpoint('Bob')
  game_endpoint = broker.endpoint('Bob', fresh: true)
  widget = GameRoomTransport.new(ProgramDouble.new(widget_endpoint))
  game_program = ProgramDouble.new(game_endpoint)
  game = GameRoomTransport.new(game_program)
  $game_room_test_user = 'Alice'
  room = owner.create_room(name: 'Discovery owner', game: 'four_in_a_row', owner: 'Alice',
    game_options: '{}', capacity: 2, private_table: visibility == :private)
  if visibility == :private
    owner.invite_user(table_id: room['__id'], user: 'Bob', metadata: {'purpose'=>'game_invitation', 'invitation_id'=>1})
  end
  $game_room_test_user = 'Bob'
  widget_row = widget.discover_rooms(include_private: true).first
  assert(widget_row, 'Widget did not discover the fixture')
  # One account, but two real owners of native sessions/callback queues.
  # The displayed object must not lend its endpoint to the new game window.
  assert(game.join_room(widget_row, 'Bob') == :joined, 'Fresh game window failed to join')
  assert(widget_endpoint.sessions.empty?, 'Game joined using the widget endpoint')
  assert(game_endpoint.sessions.length == 1, 'Game endpoint does not own membership')
  assert(game.join_room(widget_row, 'Bob') == :already_here, 'Reopening duplicated membership')
  assert(game_endpoint.sessions.length == 1, 'Repeated join added a second native session')
  game.deactivate_table(table_id: room['__id'])
  assert(game_endpoint.sessions.empty? && widget_endpoint.sessions.empty?, 'Leaving retained a native membership')

  # The same program can receive a fresh native endpoint after reconnect.
  # Objects cached before that change must not create membership on the old one.
  cached_row = game.discover_rooms(include_private: true).first
  replacement_endpoint = broker.endpoint('Bob', fresh: true)
  game_program.live_sessions = replacement_endpoint
  assert(game.join_room(cached_row, 'Bob') == :joined, 'Fresh endpoint failed to rejoin')
  assert(game_endpoint.sessions.empty?, 'Cached discovery reused the retired endpoint')
  assert(replacement_endpoint.sessions.length == 1, 'Replacement endpoint does not own membership')
  game.deactivate_table(table_id: room['__id'])
  assert(replacement_endpoint.sessions.empty?, 'Leaving retained replacement membership')
end

puts 'Discovery ownership: public/private foreign widget snapshots, own membership, reopen, endpoint change and leave passed'
