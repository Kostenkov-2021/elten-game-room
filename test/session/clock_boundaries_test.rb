require_relative "../support/card_timeout_restore"
require_relative "../support/native_live_sessions"
require_relative "../../lib/game_session_clock"

# The creator's clock epoch differs from the server. Saving a frozen game
# must keep ten seconds of the turn, not replace them with the clock skew.
[GameRoomGames::NinetyNine, GameRoomGames::Makao, GameRoomGames::Poker].each do |type|
  c = TimedCardCase.new(type.new)
  session = c.session.merge("created_at"=>100, "__server_started_at"=>100_000, "__frozen_at"=>100_010)
  snapshot = Struct.new(:session, :events).new(session, c.events)
  saves = SavedGames.new(TimedArchiveMemory.new, owner: "A")
  row = saves.put(game: c.game, table: {"owner"=>"A"}, snapshot: snapshot, repository: c.repo, now: 100_010)
  assert(row["game_time"] == 110, "#{c.game.id}: save used server epoch as game time")
  restored = saves.restored_data(row, game: c.game, table_id: 99, now: 200_000)
  fresh = session.merge("created_at"=>200_000,"__server_started_at"=>900_000,
    "__clock_offset"=>restored[:clock_offset],"__frozen_at"=>nil)
  sample, elapsed = 900_000, 0.0
  clock = GameRoomSessionClock.new(sample: -> { sample },elapsed: -> { elapsed },wall: -> { 777 })
  assert(clock.now(fresh) == 110, "restore did not retain remaining time")
  elapsed += 9
  ctx = GameRoomGames::ActionContext.new(now: clock.now(fresh),table_owner: "A")
  replay = c.game.replay(fresh,c.events,c.repo)
  assert(!c.game.automatic_action_due?(replay,"A",context:ctx), "restored timeout early")
  elapsed += 1
  ctx.now = clock.now(fresh)
  assert(c.game.automatic_action_due?(replay,"A",context:ctx), "restored timeout late")
end

# A native callback can arrive before OR after the HTTP acknowledgement.
# Minimal acknowledgements must not permanently overwrite server time with
# the creator's wall clock. Neither correction applies an event twice.
[true,false].each do |with_timestamp|
  broker = NativeLiveSessionsBroker.new
  broker.automatic_delivery = false
  endpoint = broker.endpoint("Alice")
  store = GameRoomLiveSessionStore.new(ProgramDouble.new(endpoint))
  store.instance_variable_set(:@record_clock,GameRoomSessionClock.new(sample: -> { 999 },elapsed: -> { 0 },wall: -> { 50_000 }))
  table = store.create_room(name:"Clock boundaries",game:"makao",owner:"Alice",game_options:"{}")
  guest = GameRoomLiveSessionStore.new(ProgramDouble.new(broker.endpoint("Bob")))
  guest.join_room(table,"Bob")
  core = broker.cores.values.first
  view = core.views.first
  original = view.method(:stack_push)
  view.define_singleton_method(:stack_push) do |packet, **options|
    result = original.call(packet,**options)
    entry = core.entries.last
    entry["created_at"] = 1000
    with_timestamp ? result.merge("entry"=>result["entry"].merge("created_at"=>1000)) : result
  end
  $game_room_test_user = "Alice"
  session = store.start_game(table:table,game:"makao",players:%w[Alice Bob],options:"{}",actor:"Alice")
  assert(session["__server_started_at"] == (with_timestamp ? 1000 : 999), "push used local wall time")
  count = store.send(:records_for,table["__id"]).length
  broker.deliver(duplicate: true)
  updated = store.game_session(session["__id"],table:table)
  assert(updated["__server_started_at"] == 1000, "late metadata did not correct clock boundary")
  assert(store.send(:records_for,table["__id"]).length == count, "metadata correction duplicated a record")
  boundary = store.freeze_game(updated)
  broker.deliver(duplicate:true)
  paused = store.game_session(session["__id"],table:table)
  assert(paused["__frozen_at"] == 1000, "freeze kept provisional wall time")
  assert(boundary.created_at == 1000, "freeze record was not corrected in place")
end
puts "PASS clock boundaries: timed save/restore across epochs, push metadata before/after ack, provisional correction without duplicate records"
