require_relative "support/native_live_sessions"

store = GameRoomLiveSessionStore.new(Object.new)
native = Struct.new(:metadata, :discovery_metadata, :closed?, :owner?).new({"owner" => "Alice"}, {}, false, true)
store.instance_variable_get(:@sessions)[1] = native
def projection_record(store, sequence, kind, data)
  store.send(:ingest_record, 1, sequence: sequence, message_id: "projection-#{sequence}", sender: "Alice", created_at: sequence,
    packet: {"version" => 2, "kind" => kind, "actor" => "Alice", "data" => data})
end

# Deliberate repeated historical ID: ordinary new games use fresh IDs. Preserve
# the old archive-first/action-latest lookup semantics even for this old shape.
[[1, "first", 100], [4, "later", 200]].each do |sequence, archive_id, base|
  event = {"id" => base, "sequence" => 0, "actor" => "Alice", "action" => "play", "value" => archive_id, "created_at" => 1}
  projection_record(store, sequence, "game_archive", {"archive_id" => archive_id, "index" => 0, "events" => [event]})
  projection_record(store, sequence + 1, "game_started", {"session_id" => 123, "game" => "uno", "options" => "{}",
    "players" => %w[Alice Bob], "created_at" => 1, "archive_id" => archive_id, "archive_events" => 1,
    "event_id_base" => base, "clock_offset" => 0})
  projection_record(store, sequence + 2, "game_action", {"session_id" => 123, "sequence" => 1,
    "events" => [{"action" => "draw", "value" => "", "move_id" => "move-#{sequence}"}]})
end
store.send(:records_for, 1)
calls = 0
original = store.method(:control_ledger)
store.define_singleton_method(:control_ledger) do |*args, **options|
  calls += 1
  original.call(*args, **options)
end
events = store.game_events({"table_id" => 1, "__id" => 123, "__archive_id" => "first"})
assert(events.map { |event| event["id"] } == [100, 500, 800], "archive source or live action ID base changed")
assert(events.first["value"] == "first", "later start replaced the historical imported archive")
assert(events.drop(1).all? { |event| event["__authority_user"] == "Alice" }, "shared action projection lost authority")
assert(calls == 1, "cached event projection rebuilt the control ledger per action/archive")
puts "PASS history projection preserves archive-first/action-latest sources and shares one control ledger per cached projection"
