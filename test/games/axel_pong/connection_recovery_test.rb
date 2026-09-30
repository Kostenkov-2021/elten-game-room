require_relative "../../support/pong_client"

# No epoch means registration/invitation has not completed. It is not an
# unlimited exemption from the handshake watchdog.
h = PongHarness.new
h.network.each_value { |channel| channel.epoch = nil; channel.connected = false }
h.advance(1500)
assert(h.network['bob'].resets.between?(1, 3), 'guest waits forever before the first session')
assert(h.network['alice'].resets.between?(1, 3), 'host waits forever before the first session')
h.close

# A silent open native session must be replaced too, without per-frame resets.
h = PongHarness.new
h.network.each_value { |channel| channel.drop = true }
h.advance(2000)
assert(h.network.values.all? { |channel| channel.resets.between?(1, 4) }, 'silent open channel did not retry at a bounded rate')
h.close

puts 'PASS Pong connection recovery: absent first session and silent open session have bounded retries'
