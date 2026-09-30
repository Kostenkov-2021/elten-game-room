require_relative "../../support/krowa"
require_relative "../../support/native_live_sessions"
require_relative "../../../lib/saved_games"

%w[race tower].each do |variant|
  $game_room_test_user = "Alice"
  broker = NativeLiveSessionsBroker.new
  program = ProgramDouble.new(broker.endpoint("Alice"))
  owner = GameRoomTransport.new(program)
  bob = GameRoomTransport.new(ProgramDouble.new(broker.endpoint("Bob")))
  repo = GameRepository.new(program, transport: owner, server_tables: {})
  run = KrowaTestGame.new(variant: variant, players: %w[Alice Bob])
  table = owner.create_room(name: "Krowa restore", game: "krowa", owner: "Alice", game_options: run.session["options"])
  bob.establish_membership(table_id: table["__id"], owner: "Alice", capacity: 8, user: "Bob", table: bob.discover_rooms.first)
  session = repo.start_session(table: table, game: "krowa", players: %w[Alice Bob], options: run.session["options"])
  run.context.session_id = repo.session_id(session)
  3.times do |step|
    initial = repo.snapshot_for(session, force_events: true)
    replay = run.game.replay(initial.session, initial.events, repo)
    selection = if step == 1
      {"kind" => "question", "action" => "submit", "question_id" => "krowa-answer-1", "answer" => "las"}
    else
      run.game.automatic_action(replay, "Alice", context: run.context)
    end
    status, plan = run.game.action_for(selection, replay, "Alice", context: run.context)
    assert(status == :ok, "initial native-stack action failed")
    repo.append_events(session: session, sequence: repo.next_sequence(session, initial.events), actor: "Alice", events: plan.events)
  end
  boundary = owner.freeze_game(session)
  snapshot = repo.snapshot_for(session, force_events: true)
  saves = SavedGames.new(run.program, owner: "Alice")
  row = saves.put(game: run.game, table: table, snapshot: snapshot, repository: repo, now: boundary.created_at)
  owner.deactivate_table(table_id: table["__id"])
  fresh = owner.create_room(name: "Resumed Krowa", game: "krowa", owner: "Alice", game_options: row["options"], resume_save_id: row["id"])
  bob = GameRoomTransport.new(ProgramDouble.new(broker.endpoint("Bob", fresh: true)))
  selected = bob.discover_rooms.first
  bob.establish_membership(table_id: fresh["__id"], owner: "Alice", capacity: 8, user: "Bob", table: selected)
  restored_data = saves.restored_data(row, game: run.game, table_id: fresh["__id"], now: row["saved_at"] + 86_400)
  restored = repo.restore_session(table: fresh, game: "krowa", players: restored_data[:players], options: row["options"], restore: restored_data)
  assert(repo.session_id(restored) != repo.session_id(session), "session fixture did not change")
  snap = repo.snapshot_for(restored, force_events: true)
  replay = run.game.replay(snap.session, snap.events, repo)
  assert(replay.accepted_events.length == snapshot.events.length && replay.state[:attempts].length == 1, "archive not fully replayed")
  run.context.session_id = repo.session_id(restored)
  run.context.table_id = fresh["__id"]
  selection = {"kind" => "question", "action" => "submit", "question_id" => "krowa-answer-1", "answer" => "dom"}
  status, plan = run.game.action_for(selection, replay, "Bob", context: run.context)
  assert(status == :ok, "resumed attempt refused")
  repo.append_events(session: restored, sequence: repo.next_sequence(restored, snap.events), actor: "Bob", controller: true, events: plan.events)
  snap = repo.snapshot_for(restored, force_events: true)
  replay = run.game.replay(snap.session, snap.events, repo)
  selection = run.game.automatic_action(replay, "Alice", context: run.context)
  status, plan = run.game.action_for(selection, replay, "Alice", context: run.context)
  assert(status == :ok, "resumed secret unavailable in #{variant}")
  repo.append_events(session: restored, sequence: repo.next_sequence(restored, snap.events), actor: "Alice", events: plan.events)
  remote_repo = GameRepository.new(ProgramDouble.new(broker.endpoint("Bob", fresh: true)), transport: bob, server_tables: {})
  remote_session = remote_repo.session_for_table(selected)
  remote = remote_repo.snapshot_for(remote_session, force_events: true)
  replay = run.game.replay(remote.session, remote.events, remote_repo)
  assert(replay.state[:pending].empty? && replay.state[:attempts].length == 2, "remote resumed scoring failed")
  assert(!JSON.generate(broker.cores.values.last.entries).include?('"kot"'), "private solution in shared stack")
  assert(repo.restore_session(table: fresh, game: "krowa", players: restored_data[:players], options: row["options"], restore: restored_data)["__id"] == restored["__id"], "retry duplicated game")
end
puts "Krowa: complete native-stack save/close/new table/import/score, remote replay and idempotent resume OK"
