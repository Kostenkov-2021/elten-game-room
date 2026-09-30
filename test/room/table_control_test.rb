require_relative "../../lib/table_control"
Record = Struct.new(:sequence, :sender, :packet, keyword_init: true)
def assert(value, message); raise message unless value; end
def control(seq, owner, previous: nil, session_id: 7, controllers: {}, from: seq)
  Record.new(sequence: seq, sender: owner, packet: {"kind" => "table_control", "data" => {
    "owner" => owner, "previous" => previous, "session_id" => session_id, "controllers" => controllers, "from" => from}})
end
a = control(4, "A")
b = control(12, "B", previous: GameRoomTableControl.anchor(a), controllers: {"A" => "bot"})
make = ->(rows, anchor) { GameRoomTableControl.new(founder: "A", records: rows, anchor: anchor) }
ledger = make.call([b, a], GameRoomTableControl.anchor(b))
assert(ledger.complete, "Out-of-order delivery should resolve once all records arrive")
assert(ledger.owner_at(11) == "A" && ledger.owner_at(12) == "B", "Historical authority changed retroactively")
assert(ledger.controllers(7, before: 12).empty? && ledger.controllers(7)["A"] == "bot", "Seat history boundary")
assert(ledger.controllers(8).empty?, "Controller leaked into a rematch")
assert(!make.call([b], GameRoomTableControl.anchor(b)).complete, "Missing chain must fail closed")
forged = control(13, "Mallory", previous: GameRoomTableControl.anchor(b))
assert(make.call([a, b, forged], GameRoomTableControl.anchor(b)).current_owner == "B", "Unanchored claim accepted")
changed = Marshal.load(Marshal.dump(b)); changed.packet["data"]["owner"] = "Mallory"
assert(!make.call([a, changed], GameRoomTableControl.anchor(b)).complete, "Digest mismatch accepted")
checkpoint = control(30, "B", from: 25, session_id: 8)
assert(make.call([checkpoint], GameRoomTableControl.anchor(checkpoint)).owner_at(25) == "B", "New-game checkpoint")
invalid = control(15, "B", previous: GameRoomTableControl.anchor(b), from: 1)
assert(!make.call([a,b,invalid], GameRoomTableControl.anchor(invalid)).complete, "Retroactive authority grant")
assert(make.call([], nil).current_owner == "A", "Original founder lost authority")
puts "Table control ledger: OK"
