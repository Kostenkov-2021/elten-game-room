require_relative "../../../lib/axel_pong/peer_engine"
require_relative "../../../lib/axel_pong/bot"
def assert(value, message); raise message unless value; end

# Unifying delivery must not re-tune local bot physics or strategy. Compare
# every frame with the original single-process engine, including Arcade RNG.
[false, true].each do |arcade|
  (1..6).each do |level|
    args = {bots: [0, 1], level: level, arcade: arcade}
    engines = [GameRoomPong::Engine.new(**args, rng: Random.new(55)),
      GameRoomPong::PeerEngine.new(**args, side: nil, authority: true, rng: Random.new(55))]
    engines.each do |engine|
      2.times { |side| GameRoomPong::Bot.new(side, level: level, rng: Random.new(side + 71)).step(engine) }
    end
    3000.times do |frame|
      engines.each { |engine| engine.step([{}, {}], now_ms: (frame + 1) * 16) }
      event = engines.last.take_transition
      engines.last.host_effects(event['side']) if event && event['action'] == 'hit'
      assert(engines.first.snapshot == engines.last.snapshot,
        "local bot behavior differs at level #{level}, Arcade #{arcade}, frame #{frame}")
      break if engines.first.goal
    end
  end
end

teams = [0, 0, 1, 1]
host = GameRoomPong::PeerEngine.new(side: 0, authority: true, bots: [1, 3], teams: teams)
guest = GameRoomPong::PeerEngine.new(side: 2, authority: false, bots: [1, 3], teams: teams)
assert(host.send(:controls_side?, 0) && host.send(:controls_side?, 1) && host.send(:controls_side?, 3), 'owner lost its owned seats')
assert(!host.send(:controls_side?, 2), 'owner may control a remote human')
assert(guest.send(:controls_side?, 2) && [0, 1, 3].none? { |side| guest.send(:controls_side?, side) }, 'guest may control someone else')

# A remote serve must initialize the same bot reaction/opening state as a
# local serve; the bot is never registered or run on the human guest.
remote = GameRoomPong::PeerEngine.new(side: nil, authority: true, bots: [1])
calls = []
controller = Object.new
controller.define_singleton_method(:served) { |engine, opening:| calls << [engine, opening] }
remote.register_bot(1, controller)
sender = GameRoomPong::PeerEngine.new(side: 0, authority: false, bots: [1])
assert(sender.strike(0), 'remote serve fixture')
event = sender.take_transition
assert(remote.apply_return(event), 'remote serve was rejected')
assert(calls == [[remote, true]], 'remote human serve did not initialize bot opening reaction')
assert(!remote.apply_return(event) && calls.length == 1, 'duplicate serve restarted bot reaction')

# Bot timing/width and mixed human reach stay on their old profiles.
(1..6).each do |level|
  old = GameRoomPong::Engine.new(level: level, bots: [1, 3], teams: teams)
  peer = GameRoomPong::PeerEngine.new(side: 2, authority: false, level: level, bots: [1, 3], teams: teams)
  assert(old.base_speed == peer.base_speed && old.hit_width(2) == peer.hit_width(2), 'routing changed mixed physics profile')
end
puts 'PASS unified engine: frame parity for local bots/Arcade at six levels, owned seats, remote serve reaction and unchanged physics profiles'
