require_relative "../support/ui"
require_relative "../support/log"

class Program
  def self.server_app(**_options); end
end

module Session
  def self.name
    "Alice"
  end
end

class FormTimer
  def initialize(_interval, repeat:, &callback)
    @callback = callback
  end

  def fire
    @callback.call
  end
end

class Form
  class << self
    attr_accessor :driver
  end

  alias wait_with_native_entry wait

  def wait
    raise "unexpected form wait" if Form.driver == nil
    wait_with_native_entry
    Form.driver.call(self)
  end

  def resume; end

  def focus
    fields[index].focus
  end

  def keyboard_idle_frame?
    true
  end
end

require_relative "../../__app"

def assert(condition, message)
  raise message unless condition
end

class InterfaceGameRepository
  def players_for(_session)
    ["Alice", "Bob"]
  end

  def actor_of(event, _session = nil)
    event["actor"]
  end

  def event_id(event)
    event["id"]
  end

  def session_id(session)
    session.to_h["__id"].to_i
  end
end


row = { "__id" => 7, "owner" => "Alice", "game" => "war", "status" => "waiting", "max_players" => 8, "name" => "Test room", "game_options" => "{}" }
room = LobbyRepository::TableSnapshot.new(table: row, members: ["Alice", "Bob"], bots: [])
game = GameRoomGames::FourInARow.new
game.define_singleton_method(:restart_guard_seconds) { 3 }
repository = InterfaceGameRepository.new
session = { "__id" => 1, "options" => "{}" }
active = game.replay(session, [], repository)
finished = game.replay(session, [], repository)
finished.winner = "Alice"
screen = GameScreen.new(program: Object.new, repository: repository, game: game,
  session: session, table: row, table_owner: "Alice", room_snapshot_provider: -> { room }, synchronizer: nil)
controller = Object.new
controller.define_singleton_method(:cancel) { |_lease| }
{ game: game, repository: repository, session: session, table: row, table_owner: "Alice", room_snapshot: room, surface_state: {},
  history_navigator: GameRoomHistory::Navigator.new, bot_turn_controller: controller, invite_online: ->(_table) {}, invite_contacts: ->(_table) {},
  turn_history_entries: {}, activity_entries: [] }.each { |key, value| screen.instance_variable_set("@#{key}", value) }
screen.instance_variable_set(:@activity_repository, nil)
screen.define_singleton_method(:alert) { |_message| }
screen.define_singleton_method(:getkeychar) { "" }
clock = 100.0
screen.define_singleton_method(:monotonic_time) { clock }
Form.driver = ->(_form) { screen.instance_variable_get(:@layout).back_button.trigger(:press) }
screen.send(:wait_for_action, active, [0, 0])
results = [0.0, 2.9, 3.1].map do |delay|
  clock = 101.0 + delay
  presses = 0
  Form.driver = lambda do |_form|
    layout = screen.instance_variable_get(:@layout)
    presses += 1
    raise "the finished screen kept waiting" if presses > 3
    presses == 1 ? layout.restart_button.trigger(:press) : layout.back_button.trigger(:press)
  end
  screen.send(:wait_for_action, finished, [0, 0])
end
assert(results == [nil, nil, :restart], "Restart after the final move was not delayed for #{game.restart_guard_seconds} s: #{results.inspect}")
%w[war scientific_war].each do |id|
  assert(EltenGameRoom::GAME_REGISTRY.build(id).restart_guard_seconds >= 2, "#{id} restarts at once after the final battle")
end
assert(GameRoomGames::FourInARow.new.restart_guard_seconds == 0, "the restart guard changed an unrelated game")
puts "PASS restart guard: a key held through the final battle cannot start the next game; unrelated games unchanged"
