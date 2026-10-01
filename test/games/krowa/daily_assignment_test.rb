require_relative "../../support/krowa_services"

day = "2026-10-01"
stamp = Time.utc(2026, 10, 1, 12).to_i
old_bank = KrowaTestGame.new.bank
new_bank = GameRoomGames::KrowaWordBank.new(GameRoomKrowa::WordRepository.new(
  %w[afro ksero telewizor krokodyl kwiatek palacz krowa koza mat sok rak dom las kot prosie silnia silnie]))
assert(old_bank.id_of("KOT") == new_bank.id_of("kot"), "word identity depends on position or dictionary size")
assert(old_bank.id_of("unknown") == nil, "unknown noun was assigned an identity")
encrypted = GameRoomKrowa::DailyAssignment.seal(day, "krowa")
assert(!encrypted.include?("krowa") && !encrypted.include?(old_bank.id_of("krowa")), "assignment exposes the word or its identity")
assert(GameRoomKrowa::DailyAssignment.open(day, encrypted) == "krowa", "assignment did not round-trip")
begin
  GameRoomKrowa::DailyAssignment.open("2026-10-02", encrypted)
  raise "assignment accepted for a different day"
rescue ArgumentError
end
begin
  GameRoomKrowa::DailyAssignment.open(day, encrypted.reverse)
  raise "corrupt assignment accepted"
rescue ArgumentError
end

tables = KrowaTestTables.new
store = GameRoomGames::KrowaServerStore.new(server_tables: tables, bank: old_bank, user: "Alice")
table = tables.fetch("krowa_daily_assignments")
table.lost_ack = true
assigned = store.assign_daily(day, now: stamp)
assert(assigned && table.rows.length == 1, "lost acknowledgement redrew or lost the daily word")
word = old_bank.assigned_daily(day, assigned).last
other = GameRoomGames::KrowaServerStore.new(server_tables: tables, bank: new_bank, user: "Bob")
assert(other.assign_daily(day, now: stamp) == assigned && table.rows.length == 1, "dictionary update changes today's assignment")
assert(other.daily_word(day, today: day) == nil, "today's ranking reveals the word")
assert(other.daily_word(day, today: "2026-10-02") == word, "historical ranking uses the current dictionary position")
assert(other.daily_word("2026-09-30", today: day) == nil, "unknown historical word guessed")
assert(other.assign_daily("2026-10-02", now: stamp) == nil, "client may assign a future day")

# A competing insertion receives a lower server ID while this client is
# starting. It must use that record even if its own dictionary picked another.
race_tables = KrowaTestTables.new
race_table = race_tables.fetch("krowa_daily_assignments")
race_table.define_singleton_method(:insert) do |values|
  unless @race_inserted
    @race_inserted = true
    super(values.merge("assignment" => encrypted))
  end
  super(values)
end
race_store = GameRoomGames::KrowaServerStore.new(server_tables: race_tables, bank: old_bank, user: "Alice")
assert(race_store.assign_daily(day, now: stamp) == encrypted, "concurrent starts chose different canonical words")
assert(race_table.rows.length == 2, "fixture did not create concurrent writes")

tables.enabled = false
assert(store.assign_daily(day, now: stamp) == nil, "no server silently falls back to local hashing")
missing = KrowaTestGame.new(variant: "daily")
options = JSON.parse(missing.session["options"])
options.delete("__daily_assignment")
missing.session["options"] = JSON.generate(options)
assert(missing.automatic == :missing_secret, "missing shared assignment silently recomputed")
assert(missing.game.new_game_options(options).keys.none? { |key| key.start_with?("__daily_") }, "restart retains another day's secret")
puts "PASS daily identity, encrypted day binding, concurrent/lost writes, dictionary update, history and no local fallback"
