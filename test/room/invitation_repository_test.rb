require_relative "../../lib/invitation_repository"

def assert(condition, message)
  raise message if !condition
end

pending_rows = []
transport = Object.new
def transport.pending_invitations; []; end
repository = InvitationRepository.new(transport: transport, notification_source: ->(*) { pending_rows })

table = { "__id" => 7, "status" => "waiting", "name" => "Alice's table" }

created = repository.create(table: table, sender: "Alice", recipient: "Bob", now: 100, ttl: 60)
pending_rows << created.invitation
assert(created.created?, "the first invitation was not created")
duplicate = repository.create(table: table, sender: "alice", recipient: "Bob", now: 110, ttl: 60)
assert(!duplicate.created?, "a duplicate invitation was created")

pending = repository.pending_for("Bob", tables: [table], now: 120)
assert(pending.length == 1 && pending.first.table_id == 7, "a valid invitation was not listed")
repository.respond(pending.first, recipient: "Bob", response: "accepted", now: 125)
assert(repository.pending_for("Bob", tables: [table], now: 126).empty?, "an accepted invitation remained pending")

expired = repository.create(table: table, sender: "Alice", recipient: "Carol", now: 200, ttl: 5)
pending_rows << expired.invitation
assert(expired.created?, "an invitation for another user was not created")
assert(repository.pending_for("Carol", tables: [table], now: 206).empty?, "an expired invitation remained pending")
assert(repository.pending_for("Carol", tables: [table.merge("status" => "closed")], now: 202).empty?, "a closed table invitation remained pending")

class FakeNativeInvitationTransport
  attr_reader :pending

  def initialize(pending)
    @pending = pending
  end

  def live_store?
    true
  end

  def pending_invitations
    @pending.map(&:dup)
  end
end

native_row = {
  "__id" => 91,
  "table_id" => 7,
  "sender" => "Alice",
  "recipient" => "Bob",
  "status" => "pending",
  "created_at" => 300,
  "expires_at" => 600
}
native_transport = FakeNativeInvitationTransport.new([native_row])
native_repository = InvitationRepository.new(transport: native_transport)
native_pending = native_repository.pending_for("Bob", tables: [table], now: 350)
assert(native_pending.length == 1, "a native invitation was not listed")
native_repository.respond(native_pending.first, recipient: "Bob", response: "accepted", now: 351)
assert(native_repository.pending_for("Bob", tables: [table], now: 352).empty?, "a locally resolved native invitation reappeared")

puts "Invitation repository tests passed"
