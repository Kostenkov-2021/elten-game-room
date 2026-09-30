require_relative "../support/invitation_fresh_endpoint"

[false, true].each do |private_target|
  broker = NativeLiveSessionsBroker.new
  gateway = DurableNoticeGateway.new
  alice = InvitationAppDriver.new(broker, 'Alice', gateway)
  bob = InvitationAppDriver.new(broker, 'Bob', gateway)
  $game_room_test_user = 'Alice'
  lobby = alice.instance_variable_get(:@lobby)
  repository = alice.instance_variable_get(:@games)
  game = GameRoomGames::Battleship.new
  table = lobby.create_table(name: 'Private inputs', game: game.id, owner: 'Alice',
    game_options: JSON.generate(game.default_options)).table
  carol = GameRoomTransport.new(ProgramDouble.new(broker.endpoint('Carol')))
  assert(carol.join_room(table, 'Carol') == :joined, 'Cannot join original room')
  session = repository.start_session(table: table, game: game.id, players: %w[Alice Carol],
    options: JSON.generate(game.default_options))
  start = GameRoomSimulation::Environment.new_game(game: game, players: %w[Alice Carol], seed: 11)
  # Delay starting the private phase for the late-revalidation scenario below.
  initialize_game = lambda do
    start.events.each do |event|
      repository.append_events(session: session, sequence: event['sequence'],
        events: [GameRoomGames::EventCommand.new(action: event['action'], value: event['value'])],
        actor: event['actor'], controller: true)
    end
  end
  $game_room_test_user = 'Bob'
  target = bob.transport.create_room(name: 'Invited room', game: 'uno', owner: 'Bob',
    game_options: '{}', private_table: private_target)
  assert(bob.send(:deliver_table_invitation, target, 'Alice').created?, 'Cannot invite')
  $game_room_test_user = 'Alice'
  pending = alice.send(:load_pending_invitations).find { |choice| choice[:invitation].table_id == target['__id'] }[:invitation]
  initialize_game.call
  original = broker.cores.fetch(table['__live_session_id'])
  assert(alice.send(:accept_pending_invitation, pending) == nil, 'Invitation bypassed the private-phase guard')
  assert(original.owner == 'Alice' && original.participants.values.map(&:user).sort == %w[Alice Carol], 'Blocked departure changed original room')
  assert(gateway.rows['Alice'].none?(&:revoked), 'Blocked departure consumed notification')
  assert(broker.cores.fetch(target['__live_session_id']).participants.values.none? { |person| person.user == 'Alice' }, 'Blocked departure joined target')

  # End the protected game normally; a new protected game starts during the
  # join request, after preflight. It must be rechecked under the runner lock.
  assert(alice.transport.abort_game(session), 'Could not release first private phase')
  alice.define_singleton_method(:establish_invited_table_transport) do |row|
    result = super(row)
    session = repository.start_session(table: table, game: game.id, players: %w[Alice Carol],
      options: JSON.generate(game.default_options), expected_previous_session_id: session['__id'])
    initialize_game.call
    result
  end
  assert(alice.send(:accept_pending_invitation, pending) == nil, 'Late private phase bypassed revalidation')
  assert(original.owner == 'Alice' && !original.closed && original.participants.values.map(&:user).sort == %w[Alice Carol], 'Late rejection lost original membership')
  assert(broker.cores.fetch(target['__live_session_id']).participants.values.none? { |person| person.user == 'Alice' }, 'Late rejection retained target membership')
  assert(gateway.rows['Alice'].none?(&:revoked), 'Late rejection consumed notification')
  alice.singleton_class.remove_method(:establish_invited_table_transport)
  assert(alice.transport.abort_game(session), 'Cannot end second private game')
  joined = alice.send(:accept_pending_invitation, pending)
  assert(joined && joined['__id'] == target['__id'], 'Invitation no longer works after protected phase')
  assert(original.owner == 'Carol' && !original.closed, 'Valid departure did not transfer original room')
  assert(gateway.rows['Alice'].all?(&:revoked), 'Successful join left the notification')
end
puts 'PASS invitation departure: public/private, preflight, late change, cleanup, retry and master transfer'
