require_relative "../../support/axel_pong_mouse"

api = PongMouseApi.new
native = GameRoomPong::WindowsMouse.new(api: api, window: -> { 123 })
assert(native.available?, 'injected Windows binding unavailable')
assert(native.sample == [0, 0, false], 'activation moved paddle')
api.point = [-1006, 401]
assert(native.sample == [-6, 1, false], 'relative movement / negative-monitor coordinates')
assert(native.sample == [0, 0, false], 'own pointer recentering counted as movement')
native.suspend
assert(api.point == [-1500, 200], 'cursor not restored on local exit')
native.sample
api.foreground = 555
api.point = [800, 300]
before = api.warps.length
assert(native.sample == nil && api.warps.length == before, 'moved cursor in another application')
api.foreground = 123
assert(native.sample == [0, 0, false], 'Alt+Tab return jumped')
api.modified = true
assert(native.sample == nil, 'modified shortcut became mouse input')
api.modified = false
assert(native.sample == [0, 0, false], 'modifier release jumped')
api.middle = [600, 400]
assert(native.sample == [0, 0, false], 'window resize or monitor change jumped')
api.point = [700, 450]
native.suspend
assert(api.point == [700, 450], 'exit overwrote subsequent user movement')
api.fail_warp = true
assert(native.sample == nil, 'failed recenter generated movement')
api.fail_warp = false
api.broken = true
assert(native.sample == nil, 'native read failure escaped')
api.broken = false
assert(native.sample == [0, 0, false], 'native recovery replayed old movement')
native.suspend


backend = PongMouseBackend.new
mouse = GameRoomPong::MouseControl.new(backend: backend)
input = {'move' => 0, 'hit' => false, 'press' => 0}
mouse.sample(active: true)
assert(mouse.active? && backend.samples == 1, 'mouse not active by default in playfield')
assert(!mouse.respond_to?(:toggle), 'removed mouse switch still exposed')
trace = []
16.times do |i|
  backend.delta = [10, 0]
  mouse.sample(active: true)
  trace << mouse.step(input, position: 15, now_ms: i * 16)['paddle']
  mouse.finish_frame
end
# Independently read from original bytecode: first move, then frames 8,11,14.
assert(trace == [16,16,16,16,16,16,16,17,17,17,18,18,18,19,19,19], "original repeat trace: #{trace}")
backend.delta = [-2000, 0]
mouse.sample(active: true)
assert(mouse.step(input, position: 1, now_ms: 256)['paddle'] == 18, 'reversal must move once, not teleport')
mouse.finish_frame
[[0, 200], [1, 0], [2, 1], [5, 8]].each_with_index do |delta, i|
  backend.delta = delta
  mouse.sample(active: true)
  assert(mouse.step(input, position: 15, now_ms: 272 + i * 16)['paddle'] == 18, 'vertical/noise threshold')
  mouse.finish_frame
end
backend.delta = [-2, 0]
mouse.sample(active: true)
assert(mouse.step(input, position: 15, now_ms: 400)['paddle'] == 17, 'idle >90ms did not restart immediately')
mouse.finish_frame
# Focus/native failure resets both direction and position. No jump to old X.
mouse.sample(active: false)
backend.delta = [0, 0]
mouse.sample(active: true)
assert(mouse.step(input, position: 8, now_ms: 500)['paddle'] == 8, 'focus return reused old paddle position')
mouse.finish_frame
backend.delta = nil
mouse.sample(active: true)
assert(mouse.step(input, position: 8, now_ms: 516) == input, 'native failure disabled keyboard fallback')
backend.supported = false
mouse.sample(active: true)
assert(!mouse.active?, 'native failure still captured mouse')

# With no mouse motion, the keyboard cadence stays exactly as before, even
# when mouse mode is enabled. Press counters/hits must be untouched.
[-1, 1].each do |direction|
  backend = PongMouseBackend.new
  mouse = GameRoomPong::MouseControl.new(backend: backend)

  original, adapted = GameRoomPong::Engine.new, GameRoomPong::Engine.new
  90.times do |i|
    control = input.merge('move' => direction)
    mouse.sample(active: true)
    result = mouse.step(control, position: adapted.paddles[0], now_ms: i * 16)
    original.position([control, {}], now_ms: i * 16)
    adapted.position([result, {}], now_ms: i * 16)
    assert(original.paddles == adapted.paddles, 'mouse mode changed keyboard speed/boundary')
    assert(result['press'] == 0 && result['hit'] == false, 'mouse served or hit ball')
    mouse.finish_frame
  end
end

engine = GameRoomPong::Engine.new
3.times { engine.position([{'paddle' => 18}, {}]) }
assert(engine.paddles[0] == 18, 'repeated position packet repeated movement')
assert(engine.events.count { |e| e[1] == 'step' } == 1, 'stationary pointer repeated step sound')
puts 'PASS Pong mouse: native adapter/focus/modifiers/edges/failures, original threshold and repeat trace, idle/reversal, keyboard parity and idempotent position'
