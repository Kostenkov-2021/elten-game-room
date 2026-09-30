# encoding: UTF-8
require_relative "../../support/pong_client"
require_relative "../../support/pong_audio"

# Reference expectations: the checked audio-mode routines in ap_game_start,
# ap_gamelogic, ap_ball, ap_sounds and ap_audio. No original code is executed.
failures = []
check = lambda do |name, &body|
  body.call
  puts "PASS #{name}"
rescue StandardError => error
  failures << "#{name}: #{error.message}"
end

check.call('F02: player physics roles do not depend on an observing owner') do
  [%w[Alice Bob], %w[Bob Alice], %w[Bob Carol]].each do |players|
    [false, true].each do |automatic|
      h = PongHarness.new(players: players, preferences: players.to_h { |name| [name, {'auto_return' => automatic}] })
      begin
        server_side = players.index('Alice') || 0
        h.clients.each do |name, client|
          2.times do |side|
            expected = (side == server_side ? 4.0 : 4.5) + (automatic && name == players[side] ? 0.6 : 0)
            client.engine.ball.merge!('x' => 15, 'y' => 10)
            assert((client.engine.hit_width(side) - expected).abs < 0.000001, "wrong manual/automatic hit width: #{players}/#{name}/#{side}/#{automatic}: #{client.engine.hit_width(side)} != #{expected}")
          end
        end
      ensure
        h.close
      end
    end
  end
end

check.call('F03: remote edge arrival and repeated attempts, not idle packets') do
  [%w[Alice Bob], %w[Bob Alice], %w[Bob Carol]].product([0, 1], [1.0, 29.0]).each do |players, side, edge|
    h = PongHarness.new(players: players)
    audio = nil
    begin
      h.advance(220)
      actor, listener = players[side], players[1 - side]
      program = PongAudioProgram.new
      audio = GameRoomPong::Audio.new(program, clock: -> { h.now })
      audio.load
      h.clients[listener].instance_variable_set(:@audio, audio)
      direction = edge == 1 ? -1 : 1
      h.clients[actor].engine.move_to(side, edge - direction)
      h.advance(8)
      h.clients[actor].engine.move_to(side, edge)
      h.advance(8)
      assert(program.sounds['pong_op_edge'].plays == 1, 'edge arrival sounded like an ordinary step')
      h.clients[actor].engine.move_to(side, edge + direction)
      h.advance(8)
      assert(program.sounds['pong_op_edge'].plays == 2, 'second outward attempt was silent')
      h.advance(30)
      assert(program.sounds['pong_op_edge'].plays == 2, 'stationary paddle generated edge noise')
      # Losing several replaceable packets recovers the latest attempt once,
      # without an old sound backlog or changing the reliable gameplay lane.
      channel = h.network[actor.downcase]
      channel.drop = true
      4.times { h.clients[actor].engine.move_to(side, edge + direction); h.advance(4) }
      assert(program.sounds['pong_op_edge'].plays == 2, 'fixture did not lose movement packets')
      channel.drop = false
      h.advance(12)
      assert(program.sounds['pong_op_edge'].plays == 3, 'lost edge attempt did not recover once')
      h.advance(20)
      assert(program.sounds['pong_op_edge'].plays == 3, 'recovered edge repeated in stationary snapshots')
    ensure
      h.close
    end
  end
end

check.call('F04: a playing opponent cue follows the listener without restarting') do
  program = PongAudioProgram.new
  audio = GameRoomPong::Audio.new(program)
  audio.load
  begin
    [0, 1].each do |viewer|
      %w[step edge].each do |kind|
        audio.reset
        state = GameRoomPong::Engine.new.snapshot
        state['p'][1 - viewer] = 20.0
        state['fx'] = [[1, kind, 1 - viewer, 20, 20]]
        audio.update(state, viewer: viewer, paused: false)
        sound = program.sounds[kind == 'step' ? 'pong_op_move' : 'pong_op_edge']
        before = sound.plays
        assert(sound.pan > 0, 'fixture opponent should be on the right')
        state['p'][viewer] = 25.0
        state['fx'] = []
        audio.update(state, viewer: viewer, paused: false)
        audio.tick
        assert((sound.pan - (0.56**1.4 - 1)).abs < 0.000001, 'playing cue did not move to the left')
        assert(sound.plays == before, 'pan update restarted the sound')
      end
    end
  ensure
    audio.close
  end
end

check.call('F05: original opponent shield hit gain is 0.91') do
  program = PongAudioProgram.new
  audio = GameRoomPong::Audio.new(program)
  audio.load
  begin
    state = GameRoomPong::Engine.new.snapshot
    state['fx'] = [[1, 'shield_hit', 1, 15, 20]]
    audio.update(state, viewer: 0, paused: false)
    hit = program.sounds.find { |name, sound| name.start_with?('pong_op_shield_hit') && sound.playing? }&.last
    assert(hit && (hit.volume - 0.91).abs < 0.000001, 'opponent shield hit still halved')
  ensure
    audio.close
  end
end

check.call('F06: clamp stereo after master gain, not before it') do
  program = PongAudioProgram.new
  audio = GameRoomPong::Audio.new(program)
  audio.load
  begin
    [-1.0, -0.75, -0.25, 0, 0.25, 0.75, 1.0].product([0.2, 0.5, 1.0, 2.0]).each do |pan, level|
      program.gain = 1.0
      sound = audio.send(:play_sound, 'pong_shield_on', pan: pan, level: level)
      plays = sound.plays
      [1.0, 0.5, 0.25, 1.0].each do |gain|
        program.gain = gain
        audio.tick
        left = sound.volume * (sound.pan > 0 ? 1 - sound.pan : 1)
        right = sound.volume * (sound.pan < 0 ? 1 + sound.pan : 1)
        expected_left = [level * (pan > 0 ? (1 - pan)**1.4 : 1) * gain, 1].min
        expected_right = [level * (pan < 0 ? (1 + pan)**1.4 : 1) * gain, 1].min
        assert((left - expected_left).abs < 0.000001 && (right - expected_right).abs < 0.000001,
          'wrong post-gain per-channel saturation / irreversible volume change')
        assert(sound.plays == plays, 'volume update restarted a shield sound')
      end
    end
  ensure
    audio.close
  end
end

check.call('F07: both key-down edges, left repeat priority, neutral serve aim') do
  field = GameSurfaces::PongField.new('Pong')
  keys, pressed = [0x25, 0x27], [:key_left, :key_right]
  field.define_singleton_method(:key_held?) { |key| keys.include?(key) }
  field.define_singleton_method(:key_pressed?) { |key| pressed.include?(key) }
  engine = GameRoomPong::Engine.new(paddles: [1.0, 15.0])
  field.update
  engine.position([field.input, {}])
  assert(engine.paddles[0] == 2, 'left edge then right press must end at 2, not 1')
  pressed.clear
  6.times { field.update; engine.position([field.input, {}]) }
  assert(engine.paddles[0] == 1, 'both held must repeat left on frame 7')
  keys << 0x26
  pressed << :key_up
  field.update
  engine.step([field.input, {}])
  assert(engine.ball['dy'] == 1 && engine.ball['dx'] == 0, 'both directions must serve straight')
end

check.call('F07: original key trace with pointer available/unavailable and key release') do
  backend = Object.new
  def backend.available?; true; end
  def backend.sample; [0, 0, false]; end
  def backend.suspend; end
  [false, true].each do |pointer|
    field = GameSurfaces::PongField.new('Pong')
    keys, pressed = [], []
    field.define_singleton_method(:key_held?) { |key| keys.include?(key) }
    field.define_singleton_method(:key_pressed?) { |key| pressed.include?(key) }
    mouse = GameRoomPong::MouseControl.new(backend: backend)
    mouse.sample(active: pointer)
    engine = GameRoomPong::Engine.new(paddles: [1.0, 15.0])
    # Both DOWNs: left is blocked then right moves to 2. Repeat left at 7.
    # Releasing left is not a new right DOWN; its repeat starts at frame 14.
    expected = [2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 2]
    expected.each_with_index do |position, n|
      keys.replace(n < 7 ? [0x25, 0x27] : [0x27])
      pressed.replace(n.zero? ? [:key_left, :key_right] : [])
      field.update
      input = mouse.step(field.input, position: engine.paddles[0], now_ms: (n + 1) * 16)
      engine.position([input, {}], now_ms: (n + 1) * 16)
      mouse.finish_frame
      assert(engine.paddles[0] == position, "mouse=#{pointer}, keyboard frame #{n + 1}")
    end
    assert(engine.events.count { |e| e[1] == 'edge' } == 1, 'both-DOWN edge vanished/duplicated with mouse')
    assert(engine.events.count { |e| e[1] == 'step' } == 3, 'both-DOWN steps vanished/duplicated with mouse')
  end
end

check.call('F07: counters cross clients, field recreation and a new rally safely') do
  [ [%w[Alice Bob], 'Alice'], [%w[Alice Bob], 'Bob'], [%w[Bob Carol], 'Carol'],
    [['Alice', 'bot:7:1'], 'Alice'], [['Bob', 'bot:7:1'], 'Bob'] ].each do |players, actor|
    h = PongHarness.new(players: players)
    begin
      h.advance(220)
      side = players.index(actor)
      surface = h.surfaces[actor]
      surface.controls.merge!('move' => 0, 'aim' => 0, 'left_press' => 1, 'right_press' => 1)
      h.advance(8)
      # Two complete taps have no net displacement at centre, but both count.
      authoritative = h.clients[actor].engine || h.clients['Alice'].engine
      assert(authoritative.paddles[side] == 15, 'simultaneous taps drifted')
      assert(authoritative.events.count { |e| e[1] == 'step' && e[2] == side } == 2, 'tap edges lost/repeated in client')
      # Field recreated with counters reset; then a fresh right tap.
      surface.controls.merge!('left_press' => 0, 'right_press' => 0)
      h.advance(8)
      surface.controls['right_press'] = 1
      h.advance(8)
      assert(authoritative.paddles[side] == 16, 'new field counters lost a fresh direction press')
      h.accept_point('0:0')
      h.advance(8)
      authoritative = h.clients[actor].engine || h.clients['Alice'].engine
      assert(authoritative.paddles[side] == 16, 'old direction counters moved the new rally')
      surface.define_singleton_method(:input_active?) { |_form| false }
      surface.controls['right_press'] += 1
      h.advance(8)
      assert(authoritative.paddles[side] == 16, 'queued direction edge moved the paddle outside its field')
    ensure
      h.close
    end
  end
end

check.call('F03/F07: malformed peer positions cannot create work or poison counters') do
  h = PongHarness.new
  begin
    client = h.clients['Alice']
    position = {'turn' => 0, 'goal' => nil, 'x' => 15, 'edges' => 0}
    [-1, 2**31, '1', [], nil].each do |bad|
      assert(!client.send(:valid_peer_position?, {'turn' => 0, 'goal' => nil, 'x' => 15, 'edges' => bad}),
        'invalid border counter accepted')
      body = {'paused' => false, 'state' => client.engine.snapshot.merge('edges' => [0, bad])}
      assert(!client.send(:valid_state?, body), 'invalid relayed border counter accepted')
    end
    assert(client.send(:valid_peer_position?, position), 'bounded peer position rejected')
    [-1, 2**31, '1', [], nil].each do |bad|
      assert(!client.send(:valid_peer_position?, position.merge('turn' => bad)), 'invalid turn accepted')
    end
    [nil, '15', 0, 30, Float::INFINITY, Float::NAN].each do |bad|
      assert(!client.send(:valid_peer_position?, position.merge('x' => bad)), 'invalid peer position accepted')
    end
    wire = GameRoomRealtime::Protocol.encode(match: 'm' * 24, epoch: 'e' * 16,
      sequence: 2**31 - 1, kind: 'input', body: position.merge('r' => 999, 'local' => 1))
    assert(wire.bytesize < GameRoomRealtime::Protocol::MAX_BYTES, 'new counters exceeded datagram limit')
  ensure
    h.close
  end
end

check.call('F08: final tiny serve correction is silent and not accumulated') do
  engine = GameRoomPong::Engine.new(bots: [1])
  bot = GameRoomPong::Bot.new(1, level: 2)
  engine.instance_variable_set(:@now_ms, 100)
  engine.instance_variable_get(:@step_distance)[1] = 0.99
  bot.send(:move_toward, engine, 15.03125, 0.5)
  assert(engine.paddles[1] == 15.03125, 'tiny serve correction missed its target')
  assert(engine.events.empty? && engine.instance_variable_get(:@step_distance)[1] == 0.99,
    'tiny correction changed the bot footstep accumulator')
end

abort(failures.join("\n")) unless failures.empty?
puts 'PASS all F02-F08 original-parity regressions (F01 excluded by the user)'
