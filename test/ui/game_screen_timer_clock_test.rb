require_relative "../support/ui"
require_relative "../../games/base"
require_relative "../../lib/game_screen"

def assert(value, message)
  raise message unless value
end

module Session
  def self.name; "Clock test"; end
end

game = GameRoomGames::Base.new
reads, observed, precise = 0, [], false
game.define_singleton_method(:options_from_json) { |value| reads += 1; super(value) }
game.define_singleton_method(:precise_action_clock?) { precise }
game.define_singleton_method(:timer_announcements) do |_replay, _viewer, now:|
  observed << now
  [[now.to_s, "timer #{now}"]]
end
repository = Object.new
def repository.session_id(_session); 1; end
session = {"options" => "{}", "created_at" => 1000, "__server_started_at" => 2000,
  "__clock_offset" => 3, "__frozen_at" => 2005.5}
clock = GameRoomSessionClock.new(sample: -> { 2000 }, elapsed: -> { 10.25 }, wall: -> { 1000 })
screen = GameScreen.allocate
{game: game, repository: repository, session: session, table: {"id" => 1},
  action_clock: clock, spoken_timer_announcements: {}}.each do |name, value|
  screen.instance_variable_set(:"@#{name}", value)
end
spoken = []
screen.define_singleton_method(:speak_table_automatically) { |text| spoken << text }

1000.times { screen.send(:announce_due_timers, nil) }
assert(reads.zero?, "timer reparsed game options")
assert(observed.uniq == [1002], "integer/frozen epoch clock changed")
assert(spoken == ["timer 1002"], "timer announcement dedup changed")
precise = true
screen.send(:announce_due_timers, nil)
assert(observed.last == 1002.5, "precise frozen clock lost fractions")
assert(screen.send(:action_context).now == observed.last, "action and timer clocks diverged")
assert(reads == 1, "action context must still normalize its own options")
session["__frozen_at"] = nil
session["__clock_offset"] = 0
screen.send(:announce_due_timers, nil)
assert(observed.last == 1000.0, "resume/session offset was cached")
screen.send(:announce_due_timers, nil, now: 42.75)
assert(observed.last == 42.75 && reads == 1, "explicit now changed or built context")
puts "PASS timer clock: no options/context work, integer/precise/freeze/offset, explicit now and speech dedup"
