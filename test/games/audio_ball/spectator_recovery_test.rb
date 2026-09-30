require_relative "../../support/audio_ball_relay"

h = AudioBallRelayHarness.new
h.wait_ready
old_epoch = h.network['alice'].epoch
session = h.network['alice'].instance_variable_get(:@session)
original = session.method(:send_unreliable)
quiet_until = h.now + 5.0
session.define_singleton_method(:send_unreliable) do |data, to:|
  targets = h.now < quiet_until ? to.reject { |target| target.user == 'Watcher' } : to
  original.call(data, to: targets)
end
h.advance(2000)
assert(h.network.values.all? { |channel| channel.connected? && channel.epoch == old_epoch }, 'spectator recovery disturbed the humans or did not rejoin the existing session')
assert(h.clients.values.none?(&:paused), 'spectator remains paused after fresh owner traffic and same-session rejoin')
assert(h.clients['Watcher'].engine.snapshot == h.clients['Alice'].engine.snapshot, 'recovered spectator did not restore the current authoritative snapshot')
h.press('Alice', 'prepare', 'up')
h.advance(5)
assert(h.clients['Watcher'].engine.phase == :flying, 'recovered spectator cannot follow the next flight')
h.close
assert(h.rig.endpoints.values.all?(&:closed?), 'spectator timeout recovery leaked an endpoint')
puts 'PASS Audio Ball spectator timeout: same-session rejoin and current snapshot restore without interrupting human play'
