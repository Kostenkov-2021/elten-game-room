require_relative "../../support/krowa_services"
require_relative "../../support/server_clock"

# Exercise the default daily guard, not an injected Time-returning test fetch.
previous_clock = GameRoomClock.instance_variable_get(:@clock)
previous_wall = Time.method(:now)
begin
  [-86400, 86400].each do |skew|
    stamp = Time.utc(2026, 10, 4, 22, 30).to_i
    Time.define_singleton_method(:now) { Time.at(stamp + skew) }
    clock = game_room_test_clock { stamp }
    clock.synchronize
    GameRoomClock.instance_variable_set(:@clock, clock)
    run = KrowaTestGame.new
    tables = KrowaTestTables.new
    store = GameRoomGames::KrowaServerStore.new(server_tables: tables, bank: run.bank, user: "Alice")
    guard = GameRoomGames::KrowaDailyAccess.new(run.program, user: "Alice", store: store)
    options = {"variant" => "daily"}
    assert(guard.consume(options) == true && options["__daily_day"] == "2026-10-05", "daily guard used the OS calendar")
    assert(guard.consume(options).is_a?(String), "clock skew allowed a second daily start")
  end
  GameRoomClock.instance_variable_set(:@clock, game_room_test_clock { nil })
  run = KrowaTestGame.new
  tables = KrowaTestTables.new
  store = GameRoomGames::KrowaServerStore.new(server_tables: tables, bank: run.bank, user: "Alice")
  guard = GameRoomGames::KrowaDailyAccess.new(run.program, user: "Alice", store: store)
  options = {"variant" => "daily"}
  assert(guard.consume(options).is_a?(String) && !options.key?("__daily_day"), "unconfirmed OS time authorized a daily game")
  assert(tables.fetch("krowa_daily_completions").rows.empty?, "unconfirmed time wrote a daily claim")
ensure
  Time.define_singleton_method(:now, previous_wall)
  GameRoomClock.instance_variable_set(:@clock, previous_clock)
end
puts "PASS Krowa default daily access: server date, +/-1 day local skew, repeat denied, unconfirmed clock fails closed"
