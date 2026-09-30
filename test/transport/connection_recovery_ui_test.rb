require_relative "../support/native_room_harness"
require_relative "../support/ui"
require_relative "../support/log"
require_relative "../../lib/game_surfaces"
require_relative "../../lib/game_screen"
require_relative "../../games/four_in_a_row"

module EltenAPI::Tasks
  class Cancelled < StandardError; end unless const_defined?(:Cancelled)
  def self.run(**_options)
    token = Object.new
    def token.raise_if_cancelled!; end
    yield nil, token
  end
end

class FormTimer
  def initialize(_interval, repeat:, &block); @callback = block; end
  def fire; @callback.call; end
end
class Form
  class << self; attr_accessor :driver; end
  def wait; Form.driver.call(self); end
  def keyboard_idle_frame?; true; end
  def resume; end
end

def ui_fixture
  h = NativeRoomHarness.new(game: GameRoomGames::FourInARow.new, users: %w[Alice Bob])
  h.start
  clock = [0.0]
  sync = GameRoomSync::Controller.new(transport: h.transports["Alice"], table_id: h.table["__id"],
    session_id: h.session["__id"], clock: -> { clock[0] })
  10.times { sync.next_event }
  screen = GameScreen.new(program: ProgramDouble.new(h.broker.endpoint("Alice")),
    repository: h.repositories["Alice"], game: h.game, session: h.session,
    table: h.table, table_owner: "Alice", synchronizer: sync,
    room_snapshot_provider: -> { data = h.transports["Alice"].room_snapshot(h.table); data && LobbyRepository::TableSnapshot.new(**data) })
  screen.define_singleton_method(:alert) { |text| (@test_alerts ||= []) << text }
  [h, screen, sync, clock]
end

h, paused_screen, paused_sync, _clock = ui_fixture
result = paused_screen.send(:network_task, "move") { raise GameRoomNetworkErrors::GamePaused, "The game is being saved" }
assert(result == nil && paused_sync.recovery_pending? && !paused_sync.waiting?, "save race crashed or imposed a network retry delay")
assert(paused_screen.instance_variable_get(:@test_alerts).to_a.empty?, "save race announced a network error")

h, screen, sync, clock = ui_fixture
stage = 0
reads = nil
first_replay = nil
chat = EditBox.new("Chat", text: "unfinished text")
chat.index, chat.check = 8, 3
screen.instance_variable_set(:@chat_control, chat)
screen.instance_variable_set(:@focus_location, [:chat, 0])
screen.define_singleton_method(:wait_for_action) do |replay, _revision, **_options|
  stage += 1
  case stage
  when 1
    first_replay = Marshal.dump(replay.state)
    h.broker.automatic_delivery = false
    h.write("Alice", [GameRoomGames::EventCommand.new(action: "drop", value: "1")])
    id = h.core.last_seq * GameRoomLiveSessionStore::EVENT_ID_MULTIPLIER
    @pending_event_ids = [id]
    h.view("Alice").fail_next_read = EltenAPI::LiveSessions::TimeoutError.new("snapshot timeout")
    # Force a read with native metadata that exposes a yet-unread remote entry.
    h.write("Bob", [GameRoomGames::EventCommand.new(action: "drop", value: "7")])
    reads = h.view("Alice").calls[:read]
    :refresh
  when 2
    assert(Marshal.dump(replay.state) == first_replay, "failed read replaced the last valid game")
    assert(h.view("Alice").calls[:read] == reads + 1, "cached confirmation made an extra network read")
    assert(!@pending_event_ids.empty?, "cached game falsely rejected an unverified move")
    assert(sync.waiting?, "failed ordinary read did not schedule recovery")
    assert([chat.text, chat.index, chat.check] == ["unfinished text", 8, 3], "read failure lost the chat draft")
    20.times { sync.next_event }
    assert(h.view("Alice").calls[:read] == reads + 1, "backoff still polled")
    clock[0] = 31
    assert(sync.next_event.kind == :recovery, "cached screen has no recovery wake-up")
    :refresh
  when 3
    assert(replay.accepted_events.length == 2, "recovery did not replay both moves")
    assert(@pending_event_ids.empty?, "confirmed human move stayed unresolved")
    assert(!@test_alerts.to_a.any? { |text| text.include?("Please choose again") }, "network failure was reported as an invalid move")
    :back
  else
    raise "unexpected repeated game screen"
  end
end
h.as("Alice") { assert(screen.run == :back && stage == 3, "ordinary read failure exited the room") }
puts "PASS: failed ordinary game read preserves state, pending move and chat until recovery"

h, screen, sync, clock = ui_fixture
h.broker.automatic_delivery = false
h.write("Bob", [GameRoomGames::EventCommand.new(action: "drop", value: "7")])
h.view("Alice").fail_next_read = EltenAPI::LiveSessions::TimeoutError.new("initial read timeout")
waits = 0
Form.driver = lambda do |form|
  waits += 1
  assert(sync.waiting?, "initial read did not wait for recovery")
  clock[0] = 31
  form.instance_variable_get(:@timers).each(&:fire)
end
screen.define_singleton_method(:wait_for_action) { |*_args, **_options| :back }
h.as("Alice") { assert(screen.run == :back && waits == 1, "first read failure was mistaken for closure") }
puts "PASS: failure before first snapshot waits without an empty/closed game projection"

h, screen, sync, clock = ui_fixture
sync.failed!(EltenAPI::LiveSessions::TimeoutError.new("outage"))
h.view("Alice").close
event = sync.next_event
assert(event.kind == :closed && !sync.waiting?, "confirmed closure waited for the retry timeout")
puts "PASS: confirmed room closure bypasses an unrelated network backoff"

class Program
  def self.server_app(**_options); end
end
require_relative "../../__app"

h = NativeRoomHarness.new(game: GameRoomGames::FourInARow.new, users: %w[Alice Bob])
loader = EltenGameRoom.allocate
clock = [0.0]
sync = GameRoomSync::Controller.new(transport: h.transports["Alice"], table_id: h.table["__id"], clock: -> { clock[0] })
loader.instance_variable_set(:@lobby, LobbyRepository.new(nil, transport: h.transports["Alice"], server_tables: {}))
loader.instance_variable_set(:@games, h.repositories["Alice"])
activity = Object.new
activity.define_singleton_method(:entries_for) { |*_args, **_options| [] }
loader.instance_variable_set(:@table_activity, activity)
loader.define_singleton_method(:game_definition) { |_id| h.game }
loader.define_singleton_method(:announce_server_table_access) { }
loader.define_singleton_method(:alert) { |_message| }
h.broker.automatic_delivery = false
h.transports["Alice"].update_room(h.table, { "name" => "Updated" }, actor: "Alice")
# The room read has to request a missing entry instead of using its cache.
store = h.transports["Alice"].instance_variable_get(:@live_store)
store.send(:room_state, h.table["__id"]).stack_cursor -= 1
h.view("Alice").fail_next_read = EltenAPI::LiveSessions::TimeoutError.new("room read timeout")
state = loader.send(:load_room_state, h.table, title: "Updating table", synchronizer: sync)
assert(state == :unavailable && sync.waiting?, "failed waiting-room read returned a closed room")
reads = h.view("Alice").calls[:read]
state = loader.send(:load_room_state, h.table, title: "Updating table", synchronizer: sync)
assert(state == :unavailable && h.view("Alice").calls[:read] == reads, "waiting-room retry bypassed backoff")
clock[0] = 31
state = loader.send(:load_room_state, h.table, title: "Updating table", synchronizer: sync)
assert(state.phase == :waiting, "room was not restored after read recovery")
h.view("Alice").close
state = loader.send(:load_room_state, h.table, title: "Updating table", synchronizer: sync)
assert(state.nil?, "confirmed closed room was mistaken for transient unavailability")
puts "PASS: waiting-room loader distinguishes unavailable reads from confirmed closure"
puts "Connection recovery UI tests passed: 4 cases"
