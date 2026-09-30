require_relative "../../support/pong_client"

# ELTEN owns the UI cadence. Its foreground loop waits 10 ms, and work in the
# callback adds jitter; assuming a callback exactly every 16 ms hides slowdowns.
# Go through the actual monotonic FormTimer wrapper, not only Client#frame.
def pong_timing_advance(harness, milliseconds, cadence)
  start = harness.now
  elapsed = index = 0
  while elapsed < milliseconds
    elapsed = [elapsed + cadence[index % cadence.length], milliseconds].min
    harness.now = start + elapsed / 1000.0
    harness.clients.each_value { |client| client.instance_variable_get(:@timer).update }
    index += 1
  end
end

cadences = [[8], [10], [12], [16], [17], [20], [24], [32], [40], [48], [50], [64], [8, 12, 28, 16, 40, 24]]
models = [%w[Alice Bob], ['Alice', GameRoomParticipants.bot_id(20, 1)]]
measurements = []
models.each do |players|
  (1..6).each do |level|
    cadences.each do |cadence|
      humans = players.reject { |name| GameRoomParticipants.bot?(name) }
      h = PongHarness.new(players: players, viewers: humans, options: {'difficulty' => level})
      begin
        h.advance(220)
        host = h.clients.fetch('Alice')
        server = players.fetch(host.engine.server)
        h.press(server)
        h.advance(3)
        assert(h.clients.values.none?(&:paused), 'timing fixture failed to connect')
        start_ticks = h.clients.transform_values { |client| client.engine.tick }
        start_y = h.clients.transform_values { |client| client.engine.ball['y'] }
        h.surfaces.fetch('Alice').controls['move'] = 1
        pong_timing_advance(h, 480, cadence)
        label = "#{players.last}, level #{level}, cadence #{cadence.inspect} ms"
        h.clients.each do |name, client|
          frames = client.engine.tick - start_ticks.fetch(name)
          measurements << [label, name, frames]
          # The last supplied UI wake-up may be less than the timer's 8 ms
          # after the preceding one, so one not-yet-presented frame is legal.
          # Missing six or fifteen frames (the regression) is not.
          assert((29..30).include?(frames), "#{label}: #{name} simulated #{frames} instead of 29-30 frames in 480 ms")
          expected = client.engine.ball['speed'] * frames
          actual = (client.engine.ball['y'] - start_y.fetch(name)).abs
          assert((actual - expected).abs < 0.00001, "#{label}: ball flight changed with UI cadence")
          assert(client.engine.goal == nil, "#{label}: pacing invented a goal")
        end
        # One immediate move, then frames 7, 10, 13, 16, 19, 22, 25, 28.
        assert(host.engine.paddles[0] == 24, "#{label}: held paddle has wrong real-time speed: #{host.engine.paddles[0]}")
      ensure
        h.close
      end
    end
  end
end

# A long suspension does not replay the entire gap or leave a catch-up debt.
# Short jitter is a different case from a modal window/process stall.
models.each do |players|
  humans = players.reject { |name| GameRoomParticipants.bot?(name) }
  h = PongHarness.new(players: players, viewers: humans)
  begin
    h.advance(220)
    host = h.clients.fetch('Alice')
    before = host.engine.tick
    pong_timing_advance(h, 400, [400])
    assert(host.engine.tick - before <= 1, 'long UI stall fast-forwarded the match')
    before = host.engine.tick
    pong_timing_advance(h, 160, [10])
    assert(host.engine.tick - before == 10, 'old stall debt changed subsequent timing')
    assert(host.engine.ball['dy'].zero?, 'UI stall served a stationary ball')
  ensure
    h.close
  end
end

# Different host, player and observer UI cadences must not set different game
# speeds. Reliable returns still leave the engine once per action, including
# a callback executing several short physics steps.
[%w[Alice Bob], %w[Bob Carol]].each do |players|
  h = PongHarness.new(players: players)
  begin
    h.advance(220)
    host = h.clients.fetch('Alice')
    server = players.fetch(host.engine.server)
    receiver = players.fetch(1 - host.engine.server)
    h.press(server)
    h.advance(3)
    start = h.now
    initial = h.clients.transform_values { |client| client.engine.tick }
    rates = {'Alice' => 20, 'Bob' => 32, 'Carol' => 50, 'Watcher' => 40}
    1.upto(800) do |ms|
      h.now = start + ms / 1000.0
      h.clients.each do |name, client|
        client.instance_variable_get(:@timer).update if (ms % rates.fetch(name)).zero?
      end
    end
    (['Alice'] + players).uniq.each do |name|
      assert(h.clients[name].engine.tick - initial[name] == 50, 'different clients ran at different UI-dependent speeds')
    end
    assert(h.clients.values.none?(&:paused), 'normal UI jitter caused a network pause')
    engine = h.clients[receiver].engine
    side = players.index(receiver)
    engine.ball.merge!('x' => engine.paddles[side], 'y' => side.zero? ? 4.0 : 16.0)
    h.press(receiver)
    pong_timing_advance(h, 64, [64])
    h.advance(8)
    assert(h.clients[server].engine.turn == 2, 'multi-step return missing or duplicated')
    hits = h.network[receiver.downcase].event_sent.count { |wire| JSON.parse(wire)['d']['action'] == 'hit' }
    assert(hits == 1, 'one press sent multiple reliable returns while catching up')
    assert(host.context_data['pong_point'] == nil, 'UI cadence incorrectly awarded a point')
  ensure
    h.close
  end
end

# A replay/reset resets the frame schedule as well as the input guard. Holding
# a serve key through the post-point pause must not be replayed by catch-up.
models.each do |players|
  humans = players.reject { |name| GameRoomParticipants.bot?(name) }
  h = PongHarness.new(players: players, viewers: humans)
  begin
    h.advance(220)
    h.accept_point('0:0')
    host = h.clients.fetch('Alice')
    server = players.fetch(host.engine.server)
    h.surfaces[server].controls['hit'] = true
    h.press(server)
    pong_timing_advance(h, 6000, [20, 32, 50])
    assert(host.engine.ball['dy'].zero?, 'catch-up replayed a held serve from the point pause')
    assert(!host.paused, 'jitter did not release the normal point pause')
    h.surfaces[server].controls['hit'] = false
    pong_timing_advance(h, 32, [16])
    h.press(server)
    pong_timing_advance(h, 64, [32])
    assert(host.engine.ball['dy'] != 0, 'fresh serve after the pause was lost')
  ensure
    h.close
  end
end

puts "PASS Pong real-time pacing: #{measurements.length} flight/frame checks, #{models.length * 6 * cadences.length} paddle checks, bounded stalls"
