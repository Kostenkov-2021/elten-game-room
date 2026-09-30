require_relative '../../lib/game_room_clock'

# Deterministic public ServerClock boundary for game/notification scenarios.
# The clock adapter itself is tested against the actual host implementation.
class TestServerClock
  def initialize(&sample)
    @sample = sample
  end

  def now; @sample.call; end
  def synchronized?; now != nil; end
end

def game_room_test_clock(&sample)
  GameRoomClock::Clock.new(source: TestServerClock.new(&sample))
end
