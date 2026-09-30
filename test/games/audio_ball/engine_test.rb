require_relative "../../../lib/audio_ball/engine"
require 'json'

module AudioBallEngineTest
  @tests = 0
  @assertions = 0

  def self.assert(value, message)
    @assertions += 1
    raise message unless value
  end

  def self.equal(expected, actual, message)
    assert(expected == actual, "#{message}: expected #{expected.inspect}, got #{actual.inspect}")
  end

  def self.near(expected, actual, message)
    assert((expected - actual).abs <= 1e-10, "#{message}: expected #{expected}, got #{actual}")
  end

  def self.test(name)
    yield
    @tests += 1
    puts "PASS #{name}"
  end

  def self.run
    test('first serve requires preparation and queues ordered transitions') do
      [0, 1].each do |server|
        engine = GameRoomAudioBall::Engine.new(level: 1, server: server)
        equal(:waiting, engine.phase, 'initial phase')
        equal(server, engine.holder, 'initial holder')
        equal(server == 0 ? 25.0 : 0.0, engine.position, 'initial coordinate')
        equal(nil, engine.receiver, 'initial receiver')
        equal(nil, engine.shot, 'initial shot')
        equal(nil, engine.goal, 'initial goal')
        equal(nil, engine.warning, 'initial warning')
        equal(0, engine.turn, 'initial turn')
        equal(0, engine.hits, 'initial hit count')
        assert(!engine.press(server, 'up'), 'serve skipped preparation')
        assert(!engine.press(1 - server, 'prepare'), 'opponent took possession')
        assert(engine.press(server, 'prepare'), 'holder could not prepare')
        equal(:prepared, engine.phase, 'prepared phase')
        assert(!engine.press(server, 'prepare'), 'duplicate preparation accepted')
        assert(engine.press(server, 'left'), 'prepared holder could not hit')
        equal(:flying, engine.phase, 'flight phase')
        equal(nil, engine.holder, 'holder remained during flight')
        equal(1 - server, engine.receiver, 'wrong receiver')
        equal('left', engine.shot, 'wrong shot')
        equal(4.0, engine.duration, 'initial duration')
        equal(1, engine.hits, 'hit not counted')
        equal(2, engine.turn, 'turn not advanced')
        equal({'action' => 'prepare', 'side' => server, 'turn' => 1}, engine.take_transition, 'prepare transition')
        equal({'action' => 'hit', 'side' => server, 'turn' => 2, 'shot' => 'left'}, engine.take_transition, 'hit transition')
        equal(nil, engine.take_transition, 'queue not empty')
      end
    end
    test('defense accepts only the matching shot in the final two steps') do
      [0, 1].each do |server|
        %w[up left down].each do |shot|
          engine = GameRoomAudioBall::Engine.new(server: server)
          receiver = 1 - server
          engine.press(server, 'prepare')
          engine.press(server, shot)
          assert(!engine.press(receiver, shot), 'early attempt caught the ball')
          engine.step(engine.duration * 22.999 / 25, controlled: [0, 1])
          assert(!engine.press(receiver, shot), 'defense outside two steps succeeded')
          engine.step(engine.duration * 0.001 / 25, controlled: [0, 1])
          near(receiver == 0 ? 23.0 : 2.0, engine.position, 'defense boundary coordinate')
          assert(!engine.press(server, shot), 'sender defended own shot')
          assert(!engine.press(receiver, (%w[up left down] - [shot]).first), 'wrong defense caught the ball')
          assert(!engine.press(receiver, 'prepare'), 'preparation caught the ball')
          equal(2, engine.turn, 'failed attempts changed turn')
          assert(engine.press(receiver, shot), 'boundary defense rejected')
          equal(:waiting, engine.phase, 'defense did not return to waiting')
          equal(receiver, engine.holder, 'receiver did not gain possession')
          equal(nil, engine.receiver, 'receiver persisted after catch')
          equal(nil, engine.shot, 'shot persisted after catch')
          equal(receiver == 0 ? 25.0 : 0.0, engine.position, 'caught ball not at holder')
          equal(3, engine.turn, 'defense turn')
          assert(!engine.press(receiver, shot), 'catch automatically prepared attack')
          engine.take_transition
          engine.take_transition
          equal({'action' => 'defend', 'side' => receiver, 'turn' => 3, 'shot' => shot}, engine.take_transition, 'defend transition')
          assert(engine.press(receiver, 'prepare'), 'defender could not prepare')
          assert(engine.press(receiver, 'down'), 'defender could not attack')
          equal(server, engine.receiver, 'counterattack aimed at wrong side')
          equal(5, engine.turn, 'counterattack turn')
        end
      end
    end
    test('all difficulties accelerate each flight without a gameplay floor') do
      [[1, 4.0, 1.05], [2, 2.2, 1.05], [3, 1.5, 1.05], [4, 0.9, 1.05], [5, 0.6, 1.05]].each do |level, initial, factor|
        engine = GameRoomAudioBall::Engine.new(level: level)
        expected = initial
        200.times do |index|
          holder = engine.holder
          assert(engine.press(holder, 'prepare'), 'long rally preparation failed')
          assert(engine.press(holder, %w[up left down][index % 3]), 'long rally attack failed')
          assert((engine.duration - expected).abs <= expected * 1e-12, 'flight speed sequence diverged')
          equal(index + 1, engine.hits, 'rally hit count')
          engine.step(engine.duration * 0.95)
          assert(engine.press(engine.receiver, engine.shot), 'long rally catch failed')
          equal(3 * (index + 1), engine.turn, 'rally turn sequence')
          expected /= factor
        end
        assert(engine.duration < 0.001, 'arbitrary minimum flight time stopped acceleration')
        equal(initial, GameRoomAudioBall::Engine.new(level: level).duration, 'new point did not reset speed')
      end
    end
    test('only the controlled receiver reports a flight miss and ends the rally') do
      [0, 1].each do |server|
        engine = GameRoomAudioBall::Engine.new(server: server)
        engine.press(server, 'prepare')
        engine.press(server, 'up')
        engine.take_transition
        engine.take_transition
        engine.step(engine.duration * 0.999, controlled: [0, 1])
        equal(nil, engine.goal, 'flight ended before endpoint')
        engine.step(20, controlled: [server])
        equal(:flying, engine.phase, 'sender decided remote miss')
        equal(nil, engine.goal, 'sender awarded own goal')
        equal(nil, engine.take_transition, 'unauthorized miss emitted')
        equal(server == 0 ? 0.0 : 25.0, engine.position, 'remote flight did not clamp')
        engine.step(0, controlled: [1 - server])
        equal(:over, engine.phase, 'miss did not end rally')
        equal(server, engine.goal, 'wrong goal winner')
        equal(3, engine.turn, 'miss turn')
        equal({'action' => 'miss', 'side' => 1 - server, 'turn' => 3}, engine.take_transition, 'miss transition')
        3.times { engine.step(100) }
        assert(!engine.press(server, 'prepare'), 'finished rally restarted')
        assert(!engine.press(1 - server, 'up'), 'late defense reversed goal')
        equal(nil, engine.take_transition, 'finished rally emitted more transitions')
      end
    end
    test('warning grants ten active seconds without resetting on prepare or repeats') do
      [0, 1].each do |holder|
        engine = GameRoomAudioBall::Engine.new(server: holder)
        engine.step(100_000)
        equal(nil, engine.goal, 'unwarned holding was limited')
        assert(!engine.warn(holder), 'holder warned itself')
        assert(engine.warn(1 - holder), 'opponent could not warn')
        equal(0, engine.turn, 'warning consumed a turn')
        equal(nil, engine.take_transition, 'warning entered action queue')
        equal(10.0, engine.warning, 'warning did not start at ten seconds')
        10.times { equal(10.0, engine.warning, 'pause without steps consumed warning') }
        engine.step(4)
        assert(engine.press(holder, 'prepare'), 'warned player could not prepare')
        equal(6.0, engine.warning, 'preparation reset warning')
        assert(!engine.warn(1 - holder), 'repeat warning accepted')
        equal(6.0, engine.warning, 'repeat warning extended deadline')
        engine.step(5.999)
        equal(nil, engine.goal, 'timeout before ten seconds')
        engine.step(1, controlled: [1 - holder])
        equal(nil, engine.goal, 'opponent decided timeout')
        equal(0.0, engine.warning, 'remote warning did not clamp')
        engine.step(0, controlled: [holder])
        equal(1 - holder, engine.goal, 'wrong timeout winner')
        engine.take_transition
        equal({'action' => 'miss', 'side' => holder, 'turn' => 2, 'reason' => 'timeout'}, engine.take_transition, 'timeout transition')
        assert(!engine.warn(holder), 'finished rally accepted warning')
      end
      engine = GameRoomAudioBall::Engine.new
      engine.warn(1)
      engine.press(0, 'prepare')
      engine.step(9)
      engine.press(0, 'down')
      equal(nil, engine.warning, 'attack did not clear warning')
      assert(!engine.warn(0), 'flight accepted a warning')
      engine.step(engine.duration * 0.95)
      engine.press(1, 'down')
      engine.step(1000)
      equal(nil, engine.goal, 'previous possession warning leaked to defender')
      assert(engine.warn(0), 'new holder could not be warned')
      engine.step(10)
      equal(0, engine.goal, 'waiting holder escaped timeout')
    end
    test('remote transitions preserve authority and order without consulting a second clock') do
      [0, 1].each do |server|
        local = GameRoomAudioBall::Engine.new(server: server)
        remote = GameRoomAudioBall::Engine.new(server: server)
        8.times do |index|
          actor = local.holder
          local.press(actor, 'prepare')
          prepare = local.take_transition
          assert(remote.apply(prepare), 'remote preparation rejected')
          assert(!remote.apply(prepare), 'duplicate preparation accepted')
          local.press(actor, %w[up left down][index % 3])
          hit = local.take_transition
          assert(remote.apply(hit), 'remote attack rejected')
          assert(!remote.apply(hit), 'duplicate hit accepted')
          local.step(local.duration * 0.96)
          local.press(local.receiver, local.shot)
          defend = local.take_transition
          assert(remote.apply(defend), 'remote catch checked the wrong clock')
          equal(local.turn, remote.turn, 'peer turn mismatch')
          equal(local.holder, remote.holder, 'peer holder mismatch')
          equal(local.duration, remote.duration, 'peer speed mismatch')
          equal(nil, remote.take_transition, 'imported event echoed to network')
        end
        local.press(local.holder, 'prepare')
        remote.apply(local.take_transition)
        local.press(local.holder, 'down')
        remote.apply(local.take_transition)
        local.step(local.duration)
        assert(remote.apply(local.take_transition), 'authoritative remote miss rejected')
        equal(local.goal, remote.goal, 'peer winner mismatch')
      end
    end
    test('malformed and forged remote transitions leave the current state unchanged') do
      engine = GameRoomAudioBall::Engine.new
      prepare = {'action' => 'prepare', 'side' => 0, 'turn' => 1}
      invalid = [nil, [], 'prepare', {}, prepare.transform_keys(&:to_sym)]
      {'action' => [:prepare, 'hit', 'unknown', nil], 'side' => [1, -1, 2, 0.0, '0', nil, true],
        'turn' => [0, 2, 1.0, '1', nil, true]}.each do |key, values|
        values.each { |value| invalid << prepare.merge(key => value) }
      end
      invalid << prepare.merge('shot' => 'up')
      invalid << prepare.merge('reason' => 'timeout')
      invalid << prepare.merge('extra' => 1)
      invalid.each do |data|
        assert(!engine.apply(data), "malformed preparation accepted: #{data.inspect}")
        equal(0, engine.turn, 'invalid data advanced turn')
        equal(:waiting, engine.phase, 'invalid data changed possession')
      end
      assert(!engine.apply({'action' => 'miss', 'side' => 0, 'turn' => 1}), 'unwarned holder missed')
      assert(!engine.apply({'action' => 'miss', 'side' => 0, 'turn' => 1, 'reason' => 'timeout'}), 'unwarned timeout accepted')
      assert(engine.apply(prepare), 'valid preparation failed after rejected data')
      hit = {'action' => 'hit', 'side' => 0, 'turn' => 2, 'shot' => 'up'}
      [hit.merge('side' => 1), hit.merge('shot' => :up), hit.merge('shot' => 'right'),
        hit.reject { |key, _| key == 'shot' }, hit.merge('reason' => 'timeout')].each do |data|
        assert(!engine.apply(data), 'forged hit accepted')
      end
      assert(engine.apply(hit), 'valid hit rejected')
      assert(!engine.apply({'action' => 'prepare', 'side' => 1, 'turn' => 3}), 'flight preparation accepted')
      assert(!engine.apply({'action' => 'defend', 'side' => 0, 'turn' => 3, 'shot' => 'up'}), 'sender defended remotely')
      assert(!engine.apply({'action' => 'defend', 'side' => 1, 'turn' => 3, 'shot' => 'down'}), 'wrong remote defense accepted')
      assert(!engine.apply({'action' => 'miss', 'side' => 0, 'turn' => 3}), 'sender decided own goal')
      assert(!engine.apply({'action' => 'miss', 'side' => 1, 'turn' => 3, 'reason' => 'timeout'}), 'flight timeout accepted')
      assert(engine.apply({'action' => 'defend', 'side' => 1, 'turn' => 3, 'shot' => 'up'}), 'rightful defender rejected')
      assert(!engine.apply({'action' => 'hit', 'side' => 1, 'turn' => 4, 'shot' => 'up'}), 'remote defender skipped preparation')
      engine.warn(0)
      assert(!engine.apply({'action' => 'miss', 'side' => 0, 'turn' => 4, 'reason' => 'timeout'}), 'opponent decided timeout')
      assert(engine.apply({'action' => 'miss', 'side' => 1, 'turn' => 4, 'reason' => 'timeout'}), 'warned holder timeout checked observer clock')
      equal(0, engine.goal, 'remote timeout winner')
      equal(nil, engine.take_transition, 'remote events entered outgoing queue')
    end
    test('snapshot round trips every phase and resumes motion and warning without echo') do
      [1, 2, 3, 4, 5].each do |level|
        [0, 1].each do |server|
          engine = GameRoomAudioBall::Engine.new(level: level, server: server)
          states = [engine.snapshot]
          engine.warn(1 - server)
          engine.step(2.25)
          states << engine.snapshot
          engine.press(server, 'prepare')
          states << engine.snapshot
          engine.press(server, 'left')
          engine.step(engine.duration * 0.43)
          states << engine.snapshot
          engine.step(engine.duration * 0.52)
          engine.press(1 - server, 'left')
          states << engine.snapshot
          engine.press(1 - server, 'prepare')
          engine.press(1 - server, 'down')
          engine.step(engine.duration)
          states << engine.snapshot
          states.each do |snapshot|
            equal(%w[duration goal hits holder level phase position receiver server shot turn warning], snapshot.keys.sort, 'snapshot fields')
            encoded = JSON.generate(snapshot)
            assert(encoded.bytesize < 500, 'snapshot is not compact')
            restored = GameRoomAudioBall::Engine.new
            restored.press(0, 'prepare')
            assert(restored.restore(JSON.parse(encoded)), 'valid complete snapshot rejected')
            equal(snapshot, restored.snapshot, 'restored state differs')
            equal(nil, restored.take_transition, 'restore retained stale outgoing events')
            if restored.phase == :flying
              restored.step(restored.duration)
              equal(1 - snapshot['receiver'], restored.goal, 'restored flight cannot finish')
            elsif restored.warning
              restored.step(restored.warning)
              equal(1 - snapshot['holder'], restored.goal, 'restored warning cannot finish')
            end
          end
        end
      end
      engine = GameRoomAudioBall::Engine.new
      engine.press(0, 'prepare')
      engine.press(0, 'up')
      engine.step(0.6)
      copy = GameRoomAudioBall::Engine.new
      copy.restore(engine.snapshot)
      engine.step(0.3)
      copy.step(0.3)
      near(engine.position, copy.position, 'restored flight resumed from the beginning')
      snapshot = engine.snapshot
      position = engine.position
      snapshot['position'] = 25
      snapshot['phase'].replace('over')
      equal(:flying, engine.phase, 'snapshot mutation changed phase')
      near(position, engine.position, 'snapshot mutation changed position')
    end
    test('restore rejects incomplete or inconsistent snapshots atomically') do
      engine = GameRoomAudioBall::Engine.new
      engine.press(0, 'prepare')
      engine.press(0, 'up')
      engine.step(0.5)
      baseline = engine.snapshot
      invalid = [nil, [], {}, baseline.transform_keys(&:to_sym), baseline.merge('extra' => 1)]
      baseline.each_key { |key| invalid << baseline.reject { |field, _| field == key } }
      {
        'phase' => [nil, :flying, 'bad', 'waiting', 'prepared', 'over'],
        'holder' => [0, 1, false], 'receiver' => [nil, 0, 1.0, '1', 2],
        'shot' => [nil, :up, 'right'], 'turn' => [nil, '2', 2.0, -1, 3, 200],
        'goal' => [0, 1, false], 'warning' => [0, 10, 11, -1, Float::NAN],
        'duration' => [nil, '1.5', 0, -1, 1.2, Float::INFINITY, Float::NAN],
        'position' => [nil, '10', -0.1, 25.1, Float::INFINITY, Float::NAN],
        'hits' => [nil, 0, -1, 2, 1.0, '1'], 'server' => [nil, 1, 0.0, 2],
        'level' => [nil, 0, 2, 5, 1.0, '1']
      }.each do |key, values|
        values.each { |value| invalid << baseline.merge(key => value) }
      end
      invalid.each do |data|
        assert(!engine.restore(data), "invalid snapshot accepted: #{data.inspect}")
        equal(baseline, engine.snapshot, 'rejected restore partially changed state')
      end
      equal('prepare', engine.take_transition['action'], 'rejected restore lost queued actions')
      equal('hit', engine.take_transition['action'], 'rejected restore lost queued hit')
      waiting = GameRoomAudioBall::Engine.new.snapshot
      [waiting.merge('holder' => 1), waiting.merge('position' => 0), waiting.merge('receiver' => 1),
        waiting.merge('shot' => 'up'), waiting.merge('turn' => 3), waiting.merge('warning' => '10'),
        waiting.merge('warning' => 10.1), waiting.merge('warning' => -0.1)].each do |data|
        assert(!engine.restore(data), 'impossible waiting snapshot accepted')
      end
      [false, true].each do |prepared|
        timed = GameRoomAudioBall::Engine.new
        timed.warn(1)
        timed.press(0, 'prepare') if prepared
        timed.step(10)
        assert(engine.restore(timed.snapshot), 'valid timeout ending rejected')
        assert(!engine.restore(timed.snapshot.merge('goal' => 0)), 'wrong timeout winner restored')
        assert(!engine.restore(timed.snapshot.merge('position' => 0)), 'wrong timeout endpoint restored')
        assert(!engine.restore(timed.snapshot.merge('warning' => 0)), 'ended warning restored')
      end
      observer = GameRoomAudioBall::Engine.new
      assert(observer.restore(baseline), 'mid-flight observer snapshot rejected')
      assert(observer.apply({'action' => 'defend', 'side' => 1, 'turn' => 3, 'shot' => 'up'}), 'observer lost snapshot turn on next action')
    end
    test('local arguments reject invalid types and nonfinite time without changing state') do
      [nil, 0, 6, '1', 1.0, true].each do |level|
        begin
          GameRoomAudioBall::Engine.new(level: level)
          assert(false, 'invalid level accepted')
        rescue ArgumentError
          assert(true, 'invalid level rejected')
        end
      end
      [nil, -1, 2, '0', 0.0, true].each do |side|
        begin
          GameRoomAudioBall::Engine.new(server: side)
          assert(false, 'invalid server accepted')
        rescue ArgumentError
          assert(true, 'invalid server rejected')
        end
      end
      engine = GameRoomAudioBall::Engine.new
      [nil, -1, 2, '0', 0.0, true].each do |side|
        assert(!engine.press(side, 'prepare'), 'invalid actor accepted')
      end
      [nil, -1, 2, '1', 1.0, true].each do |side|
        assert(!engine.warn(side), 'invalid warning actor accepted')
      end
      [nil, :prepare, 'Prepare', 'right', 1, true].each do |command|
        assert(!engine.press(0, command), 'invalid command accepted')
      end
      engine.press(0, 'prepare')
      engine.press(0, 'down')
      baseline = engine.snapshot
      [nil, -1, '0.1', Float::NAN, Float::INFINITY, -Float::INFINITY, true].each do |seconds|
        begin
          engine.step(seconds)
          assert(false, 'invalid time accepted')
        rescue ArgumentError
          equal(baseline, engine.snapshot, 'invalid time changed state')
        end
      end
      [nil, 0, '0', [0.0], [2], ['1'], [true]].each do |controlled|
        begin
          engine.step(0.1, controlled: controlled)
          assert(false, 'invalid controlled sides accepted')
        rescue ArgumentError
          equal(baseline, engine.snapshot, 'invalid controllers advanced motion')
        end
      end
    end
    test('queued shots do not alias mutable caller strings') do
      engine = GameRoomAudioBall::Engine.new
      command = +'up'
      engine.press(0, 'prepare')
      engine.press(0, command)
      command.replace('down')
      engine.take_transition
      equal('up', engine.take_transition['shot'], 'caller changed queued shot after acceptance')
      equal('up', engine.shot, 'caller changed active shot after acceptance')
    end
    test('fractional frames reach the same exact deadline as one step') do
      engine = GameRoomAudioBall::Engine.new
      engine.warn(1)
      99.times { engine.step(0.1) }
      equal(nil, engine.goal, 'fractional warning expired early')
      engine.step(0.1)
      equal(1, engine.goal, 'fractional warning missed ten-second deadline')
      [1, 2, 3, 4, 5].each do |level|
        engine = GameRoomAudioBall::Engine.new(level: level)
        engine.press(0, 'prepare')
        engine.press(0, 'up')
        frame = engine.duration / 100
        99.times { engine.step(frame) }
        equal(nil, engine.goal, 'fractional flight ended early')
        engine.step(frame)
        equal(0, engine.goal, 'fractional flight did not reach endpoint')
      end
    end
    puts "PASS Audio Ball engine: #{@tests} tests, #{@assertions} assertions"
  end
end

AudioBallEngineTest.run
