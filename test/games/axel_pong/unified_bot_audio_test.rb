require_relative "../../support/pong_client"

h = PongHarness.new(players: ['Alice', 'Bob', 'bot:7:1', 'bot:7:2'], viewers: %w[Alice Bob Watcher],
  options: {'team_size' => 2, 'team_seats' => [0, 0, 1, 1]})
begin
  h.advance(80)
  host, guest = h.clients['Alice'].engine, h.clients['Bob'].engine
  count = ->(engine) { engine.events.count { |_, kind, side, *_| kind == 'step' && side == 2 } }
  host.move_to(2, 15.2)
  h.advance(4)
  assert(count.call(host).zero? && count.call(guest).zero?, 'remote client sounded a silent fractional bot move')
  host.move_to(2, 16.2)
  h.advance(4)
  assert(count.call(host) == 1 && count.call(guest) == 1, 'remote bot step was missing or repeated')
  h.advance(10)
  assert(count.call(guest) == 1, 'repeated position snapshot repeated bot audio')
  assert(guest.paddles[2] == host.paddles[2], 'suppressing invented bot steps lost its position')
  host.move_to(2, 16.4)
  h.advance(4)
  assert(count.call(guest) == 1, 'small follow-up move invented another bot step')
ensure
  h.close
end
puts 'PASS unified remote bot audio: fractional silent moves, original owner cue, no repeated snapshot steps and up-to-date position'
