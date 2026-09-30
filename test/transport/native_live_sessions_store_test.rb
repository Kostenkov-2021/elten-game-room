require_relative "../support/native_live_sessions"
require_relative "../../lib/game_room_server_tables"

[false, true].each do |denied|
  broker = NativeLiveSessionsBroker.new
  users = %w[Alice Bob Carol Dave]
  transports = users.to_h do |user|
    [user, GameRoomTransport.new(ProgramDouble.new(broker.endpoint(user)))]
  end
  activity_table = ActivityTableDouble.new(denied: denied)
  server_program = Struct.new(:server_app_uuid).new("server-uuid")
  server_tables = users.to_h do |user|
    provider = GameRoomServerTables.new(server_program, client: activity_table)
    assert(provider.check_access(username: user) == !denied, "Table access detection disagreed with the server")
    [user, provider]
  end
  activities = users.to_h do |user|
    [user, TableActivityRepository.new(server_tables: server_tables.fetch(user), transport: transports.fetch(user))]
  end
  lobbies = users.to_h do |user|
    [user, LobbyRepository.new(ProgramDouble.new(broker.endpoint(user)), transport: transports.fetch(user), server_tables: server_tables.fetch(user), activity_repository: activities.fetch(user))]
  end
  games = users.to_h do |user|
    [user, GameRepository.new(ProgramDouble.new(broker.endpoint(user)), transport: transports.fetch(user), server_tables: server_tables.fetch(user))]
  end

  users.each { |user| transports.fetch(user).start }
  $game_room_test_user = "Alice"
  created = lobbies.fetch("Alice").create_table(name: "Alice's table", game: "four_in_a_row", owner: "Alice", game_options: "{}")
  assert(created.created?, "native room was not created")
  table = created.table

  $game_room_test_user = "Bob"
  bob_public = lobbies.fetch("Bob").open_tables.first
  assert(bob_public && bob_public["__id"] == table["__id"], "public LiveSession was not discovered")
  assert(transports.fetch("Bob").establish_membership(table_id: table["__id"], owner: "Alice", capacity: 8, user: "Bob", table: bob_public), "Bob could not join")
  bob_join = lobbies.fetch("Bob").join_table(bob_public, "Bob")
  assert(bob_join.status == :joined, "new native membership was not reported as joined")

  $game_room_test_user = "Alice"
  alice_snapshot = lobbies.fetch("Alice").snapshot_for(table)
  assert(alice_snapshot.members.sort == %w[Alice Bob], "room membership did not synchronize")
  bot_result = lobbies.fetch("Alice").add_bot(table, snapshot: alice_snapshot)
  assert(bot_result.updated? && bot_result.snapshot.participants.length == 3, "bot room state did not synchronize")

  invitations = users.to_h { |user| [user, InvitationRepository.new(transport: transports.fetch(user))] }
  sent = invitations.fetch("Alice").create(table: table, sender: "Alice", recipient: "Carol")
  transports.fetch("Alice").invite_user(
    table_id: table["__id"],
    user: "Carol",
    metadata: { "purpose" => "game_invitation", "invitation_id" => sent.invitation["__id"] }
  )
  $game_room_test_user = "Carol"
  pending = invitations.fetch("Carol").pending_for("Carol", tables: lobbies.fetch("Carol").open_tables)
  assert(pending.length == 1, "native invitation was not exposed")
  assert(transports.fetch("Carol").establish_membership(table_id: table["__id"], owner: "Alice", capacity: 8, user: "Carol", invitation_id: pending.first.id, table: pending.first.table), "native invitation was not accepted")
  carol_join = lobbies.fetch("Carol").join_table(pending.first.table, "Carol")
  assert(carol_join.status == :joined, "accepted invitation was not recorded as a join")

  $game_room_test_user = "Dave"
  dave_public = lobbies.fetch("Dave").open_tables.first
  assert(transports.fetch("Dave").establish_membership(table_id: table["__id"], owner: "Alice", capacity: 8, user: "Dave", table: dave_public), "Dave could not join")
  assert(lobbies.fetch("Dave").join_table(dave_public, "Dave").status == :joined, "fourth client was not recorded")

  $game_room_test_user = "Alice"
  # The complete name assignment travels atomically with the bot count.
  owner_lobby = lobbies.fetch("Alice")
  2.times { assert(owner_lobby.add_bot(table, snapshot: owner_lobby.snapshot_for(table)).updated?, "could not add a test computer") }
  remaining_bots = owner_lobby.snapshot_for(table).bots.first(2)
  removed = owner_lobby.remove_bot(table, snapshot: owner_lobby.snapshot_for(table))
  assert(removed.updated?, "count-only computer removal failed")
  users.each do |user|
    snapshot = lobbies.fetch(user).snapshot_for(table)
    assert(snapshot.table["bot_count"] == 2, "#{user} did not receive the smaller bot count")
    assert(snapshot.bots == remaining_bots, "#{user} lost computer identities/names")
    assert(snapshot.bots.map { |bot| GameRoomParticipants.bot_number(bot) } == [1, 2], "computer slots are not contiguous")
  end
  added = owner_lobby.add_bot(table, snapshot: owner_lobby.snapshot_for(table))
  assert(GameRoomParticipants.bot_number(added.snapshot.bots.last) == 3, "adding after removal changed the existing numbering convention")
  core = broker.cores.values.first
  assert(core.metadata["protocol"] == 7, "clients without controller history support must not join new tables")
  packets = core.entries.map { |entry| entry.fetch("packet") }
  assert(packets.all? { |packet| packet["version"] == 2 }, "UI refactor changed the stack protocol")
  bot_updates = packets.select { |packet| packet["kind"] == "room_state" && packet["data"].key?("bot_count") }
  assert(bot_updates.all? { |packet| packet["data"].keys.sort == %w[bot_count bot_names updated_at] }, "computer count and names were not sent together")

  players = lobbies.fetch("Alice").snapshot_for(table).participants
  session = games.fetch("Alice").start_session(table: table, game: "four_in_a_row", players: players, options: "{}")
  events = [GameRoomGames::EventCommand.new(action: "drop", value: "1")]
  saved = games.fetch("Alice").append_events(session: session, sequence: 1, events: events, actor: "Alice")
  assert(saved.length == 1, "atomic stack action was not stored")

  threads = %w[Bob Carol].map do |user|
    Thread.new do
      Thread.current[:game_room_test_user] = user
      remote_session = games.fetch(user).session_for_table(lobbies.fetch(user).current_table_for(user))
      games.fetch(user).append_events(
        session: remote_session,
        sequence: 2,
        events: [GameRoomGames::EventCommand.new(action: "simultaneous", value: user)],
        actor: user
      )
    end
  end
  threads.each(&:join)

  $game_room_test_user = "Bob"
  bob_session = games.fetch("Bob").session_for_table(bob_public)
  bob_snapshot = games.fetch("Bob").snapshot_for(bob_session)
  assert(bob_snapshot.events.map { |event| event["action"] } == ["drop", "simultaneous", "simultaneous"], "game stack did not preserve concurrent actions")
  assert(bob_snapshot.events.last(2).map { |event| event["actor"] }.sort == %w[Bob Carol], "one concurrent client action was lost")

  $game_room_test_user = "Dave"
  dave_session = games.fetch("Dave").session_for_table(dave_public)
  assert(games.fetch("Dave").snapshot_for(dave_session).events.map { |event| event["__id"] } == bob_snapshot.events.map { |event| event["__id"] }, "four clients did not converge on one stack order")

  chat = activities.fetch("Bob").append(table: bob_public, kind: "chat", message: "Hello", actor: "Bob")
  assert(chat && activities.fetch("Alice").entries_for(table).any? { |entry| entry.kind == "chat" && entry.message == "Hello" }, "chat did not use the shared room stack")

  history_item = Struct.new(:text, :event_id).new("Alice played.", bob_snapshot.events.first["__id"])
  merged_history = activities.fetch("Alice").merged_history_entries(
    game_entries: [history_item],
    game_events: bob_snapshot.events,
    activity_entries: activities.fetch("Alice").entries_for(table),
    game_name: ->(id) { id.to_s }
  )
  assert(
    [:game, :chat, :room].all? { |category| merged_history.any? { |entry| entry.category == category } },
    "separate game, chat and room history categories were lost"
  )

  $game_room_test_user = "Alice"
  assert(lobbies.fetch("Alice").close_table(table), "owner could not close native room")
  $game_room_test_user = "Bob"
  assert(lobbies.fetch("Bob").open_tables.empty?, "closed LiveSession remained discoverable")

  assert(activity_table.calls == Array.new(users.length, :select), "Table requests continued after the four startup denials") if denied

end

puts "Native LiveSessions store tests passed: discovery, membership, invitations, room state, game stack, chat and cleanup, with and without table access"
