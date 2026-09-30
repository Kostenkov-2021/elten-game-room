require_relative "../support/native_live_sessions"
require_relative "../../lib/account_saved_games"
require_relative "../support/private_archives"

resources = PrivateArchiveDouble.new
program = Object.new
def program.read_json(*); raise "local disk accessed"; end
def program.update_json(*); raise "local disk written"; end
store = AccountSavedGames.new(program, owner: "Alice", resources: resources)
row = {"id" => SecureRandom.uuid, "owner" => "Alice", "game" => "uno", "saved_at" => 123,
  "players" => ["Alice", "Bob"], "events" => Array.new(3000) { {"value" => "Polskie żółte karty"} }}
row["checksum"] = store.send(:checksum, row)
resources.lost_reply = true
assert(store.persist(row) == row, "lost acknowledgement must reconcile exact archive")
assert(store.list.length == 1 && !store.list.first.key?("events"), "list must be a lazy manifest")
assert(store.fetch(row["id"]) == row, "new account-backed reader must reconstruct exact JSON")
other = AccountSavedGames.new(program, owner: "Bob", resources: resources)
assert(other.list.empty? && !other.delete(row["id"]), "foreign owner manifest rejected")
resources.corrupt = true
begin
  store.fetch(row["id"])
  raise "corrupt archive accepted"
rescue IOError
end
resources.corrupt = false
resources.lost_delete_reply = true
assert(store.delete(row["id"]) && store.list.empty?, "confirmed deletion")
resources.quota = 0
begin
  store.persist(row)
  raise "zero quota accepted"
rescue IOError
end
puts "Private archive: exact compressed roundtrip, lazy list, checksum, owner, lost reply, quota and deletion passed"
