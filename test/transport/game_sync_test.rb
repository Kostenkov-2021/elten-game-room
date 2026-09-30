require_relative "../../lib/game_sync"

def assert(condition, message)
  raise message if !condition
end

class FakeSyncTransport
  attr_reader :table_changes, :game_changes, :game_starts, :recoveries

  def initialize
    @table_changes = {}
    @game_changes = {}
    @game_starts = {}
    @recoveries = {}
  end

  def consume_table_change(table_id)
    @table_changes.delete(table_id) == true
  end

  def consume_game_change(session_id)
    @game_changes.delete(session_id)
  end

  def consume_game_start(table_id)
    @game_starts.delete(table_id)
  end

  def consume_recovery(table_id)
    @recoveries.delete(table_id) == true
  end
end

now = 100.0
transport = FakeSyncTransport.new
reconnects = 0
controller = GameRoomSync::Controller.new(
  transport: transport,
  table_id: 7,
  session_id: 11,
  reconnect: -> { reconnects += 1 },
  clock: -> { now }
)

assert(controller.next_reconcile_at.infinite?, "periodic reconciliation was not disabled")
assert(controller.next_event == nil, "reconciliation ran before it was due")

transport.recoveries[7] = true
event = controller.next_event
assert(event.kind == :recovery, "a LiveSessions gap was blocked by keyboard activity")

transport.game_starts[7] = 12
transport.game_changes[11] = 99.5
transport.table_changes[7] = true
event = controller.next_event
assert(event.kind == :game_started && event.session_id == 12, "a new game did not have first priority")
event = controller.next_event
assert(event.kind == :game_changed && event.received_at == 99.5, "a game change lost its receive time")
event = controller.next_event
assert(event.kind == :table_changed, "a table change was not returned after the game change")

now = 103.0
assert(controller.next_event == nil, "a periodic reconciliation still ran")
controller.request_recovery!
assert(controller.next_event(allow_recovery: false) == nil, "a caller could not postpone recovery")
event = controller.next_event
assert(event.kind == :recovery, "requested recovery was not returned")

now = 104.0
result = controller.synchronize { :current }
assert(result == :current && reconnects == 1, "synchronization did not reconnect before reading state")
assert(controller.next_reconcile_at.infinite?, "successful synchronization did not disable polling again")

begin
  controller.synchronize { raise GameRoomNetworkErrors::UncertainWrite, "temporary network failure" }
rescue StandardError
end
assert(controller.next_reconcile_at == 134.0, "a normal failure did not use the shared backoff")

now = 140.0
begin
  controller.synchronize { raise GameRoomNetworkErrors::UncertainWrite, "HTTP 429: Too many requests" }
rescue StandardError
end
assert(controller.next_reconcile_at == 200.0, "a rate limit did not use the longer shared backoff")

transport.game_changes[15] = 142.0
controller.update_session(15, discard_pending: true)
assert(!transport.game_changes.key?(15), "switching games did not discard its already handled notification")

puts "Game synchronization tests passed"

controller.synchronized!
fault = NoMethodError.new('callback programming fault')
transport.define_singleton_method(:consume_recovery) { |_| fault }
begin
  controller.next_event
  raise 'callback programming error was swallowed'
rescue NoMethodError => error
  assert(error.equal?(fault) && !controller.recovery_pending?, 'internal error became an outage')
end
