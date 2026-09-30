require_relative "../support/saved_games_ui"

broker = NativeLiveSessionsBroker.new
app = SaveAppDriver.new(broker)
$game_room_test_user = "Alice"
game = GameRoomGames::TicTacToe.new
table = app.lobby.create_table(name: "Observer save",game: game.id,owner: "Alice",game_options: "{}").table
app.lobby.set_observer(table,"Alice",true)
guests = %w[Bob Carol].to_h do |name|
  guest = GameRoomTransport.new(ProgramDouble.new(broker.endpoint(name)))
  assert(guest.establish_membership(table_id: table["__id"],owner: "Alice",capacity: 8,user: name,table: guest.discover_rooms.first), "guest could not join")
  [name, guest]
end
session = app.games.start_session(table: table,game: game.id,players: %w[Bob Carol],options: "{}")
env = GameRoomSimulation::Environment.new_game(game: game,players: %w[Bob Carol],seed: 1)
env.step(game.legal_actions(env.replay,"Bob",context: env.context).first,actor: "Bob")
$game_room_test_user = "Bob"
bob_repo = GameRepository.new(ProgramDouble.new(broker.endpoint("Bob")),transport: guests["Bob"],server_tables: {})
env.events.each do |event|
  bob_repo.append_events(session: session,sequence: event["sequence"],
    events: [GameRoomGames::EventCommand.new(action: event["action"],value: event["value"])],actor: "Bob")
end
$game_room_test_user = "Alice"
assert(app.send(:save_current_game,table,session,game), "observer owner could not save")
saved = app.send(:saved_games).fetch(app.send(:saved_games).list.first["id"])
assert(saved["players"] == %w[Bob Carol] && saved["owner"] == "Alice", "owner substituted for player")
assert(saved["events"].length == 1, "save fixture has no actual move")
new_table = app.send(:create_saved_game_table,saved)
assert(new_table && app.room_state(new_table).room.observers.include?("Alice"), "restored founder is not an observer")
assert(app.send(:resume_saved_game_at_table,new_table,app.room_state(new_table)) == nil, "missing seats silently filled")
%w[Bob Carol].each do |name|
  guest = GameRoomTransport.new(ProgramDouble.new(broker.endpoint(name,fresh: true)))
  assert(guest.establish_membership(table_id: new_table["__id"],owner: "Alice",capacity: 8,user: name,table: guest.discover_rooms.first), "guest could not rejoin")
end
resumed = app.send(:resume_saved_game_at_table,new_table,app.room_state(new_table))
assert(resumed && app.games.players_for(resumed) == %w[Bob Carol], "restore changed seats")
snapshot = app.games.snapshot_for(resumed)
replayed = game.replay(snapshot.session,snapshot.events,app.games)
assert(replayed.board == env.replay.board && replayed.current_player == "Carol", "restore lost board or next player")
assert(app.room_state(new_table).room.observers.include?("Alice"), "start removed observer role")
begin
  GameRoomSavedGameArchive.new(app,owner: "Bob").validate(saved,game: game)
  raise "foreign archive accepted"
rescue ArgumentError
end
puts "PASS owner-observer: save/close/create/invite/wait/restore original seats and preserve archive ownership"
