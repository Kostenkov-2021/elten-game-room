require_relative "../../support/pong_mixed"

# The shared preview precedes the durable score without changing that score
# or extending the existing post-goal/serve schedule.
[0, 16, 48, 375].each do |write_delay|
  h = mixed_goal_match
  begin
    concede_mixed_goal(h)
    value = await_mixed_point(h)
    assert(h.clients.keys.all? { |n| mixed_audio(h, n).goals.length == 1 }, 'goal audio waited for LiveSessions')
    times = h.clients.keys.to_h { |n| [n, mixed_audio(h, n).goals.first[:at]] }
    h.advance(write_delay)
    assert(h.replay.state[:rally].zero? && h.replay.state[:scores] == [0, 0], 'preview changed durable score')
    assert(h.clients.keys.all? { |n| mixed_audio(h, n).points.empty? }, 'preview spoke an unconfirmed score')
    deliver_mixed_point(h, value)
    h.clients.each do |name, client|
      audio = mixed_audio(h, name)
      assert(audio.goals.length == 1 && audio.points.length == 1, 'durable confirmation repeated goal')
      assert(audio.points.first[:goal_at] == times[name], 'durable score forgot preview time')
      expected = [h.now, times[name] + 3.0].max + 2.7
      assert((client.send(:rally_state).ready_at - expected).abs < 0.000001, 'write added another serve pause')
    end
  ensure
    h.close
  end
end

h = mixed_goal_match
begin
  h.network['carol'].drop = true
  concede_mixed_goal(h)
  h.advance(8)
  assert(h.clients['Alice'].engine.goal != nil && !h.clients['Alice'].context_data['pong_point'], 'missing acknowledgement fixture')
  assert(h.clients.keys.all? { |n| mixed_audio(h, n).goals.empty? }, 'unacknowledged goal sounded')
  h.network['carol'].drop = false
  deliver_mixed_point(h, await_mixed_point(h))
ensure
  h.close
end

# Reliable point overtakes observer snapshot: the common bounded event queue
# retains it until the matching state, not a special bot confirmation queue.
h = mixed_goal_match
begin
  source = h.network['alice']
  original = source.method(:send)
  held = nil
  source.define_singleton_method(:send) do |data|
    result = original.call(data)
    snapshot = h.network['watcher'].inbox.delete('alice')
    held = snapshot if snapshot
    result
  end
  concede_mixed_goal(h)
  await_mixed_point(h)
  assert(mixed_audio(h, 'Bob').goals.length == 1 && mixed_audio(h, 'Watcher').goals.empty?, 'observer skipped state agreement')
  assert(h.clients['Watcher'].send(:rally_state).deferred_events.any? { |_, p| p.dig('d', 'action') == 'point' },
    'early observer point was lost')
  source.define_singleton_method(:send, original)
  h.network['watcher'].inbox['alice'] = held
  h.advance(2)
  assert(mixed_audio(h, 'Watcher').goals.length == 1, 'late snapshot did not release point sound')
ensure
  h.close
end

h = mixed_goal_match
begin
  hold_mixed_point(h)
  concede_mixed_goal(h)
  value = await_mixed_point(h)
  packet = JSON.parse(h.network['alice'].event_sent.last)
  assert(packet.dig('d', 'action') == 'point', 'mixed match invented another confirmation type')
  bad = [packet['d'].merge('r' => -1), packet['d'].merge('side' => 2),
    packet['d'].merge('turn' => 0), packet['d'].merge('side' => 1 - packet['d']['side'])]
  bad.each { |data| h.network['bob'].event_inbox << ['alice', packet.merge('d' => data)] }
  h.network['bob'].event_inbox << ['carol', packet]
  h.advance(1)
  assert(mixed_audio(h, 'Bob').goals.empty?, 'invalid owner point was announced')
  h.network['alice'].release_events
  h.advance(2)
  3.times { h.network['bob'].event_inbox << ['alice', packet] }
  h.advance(2)
  assert(mixed_audio(h, 'Bob').goals.length == 1, 'duplicate point repeated sound')
  deliver_mixed_point(h, value)
  h.network['bob'].event_inbox << ['alice', packet]
  h.advance(2)
  assert(mixed_audio(h, 'Bob').goals.length == 1, 'old-rally point repeated audio')
ensure
  h.close
end

# Durable fallback when reliable preview is late; agreed points also survive
# reconnect without starting a new rally or replaying the goal.
[
  ['Alice', 'Bob', 'Carol', 'bot:7:1'], ['Bob', 'Carol', 'Dave', 'bot:7:1'],
  ['Alice', 'bot:7:1', 'bot:7:2', 'bot:7:3'], ['Bob', 'bot:7:1', 'bot:7:2', 'bot:7:3'],
  ['Alice', 'bot:7:1'], ['Bob', 'bot:7:1']
].each do |players|
  [false, true].each do |reconnect|
    h = mixed_goal_match(players)
    begin
      hold_mixed_point(h) unless reconnect
      concede_mixed_goal(h)
      value = await_mixed_point(h)
      if reconnect
        h.network.each_value { |channel| channel.epoch = 'replacement' }
        h.advance(100)
        assert(h.clients['Alice'].context_data['pong_point'] == value, 'agreed point disappeared on reconnect')
        assert(h.clients['Alice'].engine.ball['dy'].zero? && h.replay.state[:rally].zero?, 'recovery replayed agreed rally')
      end
      deliver_mixed_point(h, value)
      h.network['alice'].release_events
      h.advance(5)
      assert(h.clients.keys.all? { |n| mixed_audio(h, n).goals.length == 1 }, 'goal was lost or repeated')
    ensure
      h.close
    end
  end
end

h = mixed_goal_match
begin
  h.network['carol'].drop = true
  concede_mixed_goal(h)
  h.advance(350)
  assert(!h.clients['Alice'].context_data['pong_point'], 'missing player removed from agreement')
  assert(h.clients.keys.all? { |n| mixed_audio(h, n).goals.empty? }, 'outage caused an unagreed preview')
  h.network['carol'].drop = false
  h.network.each_value { |channel| channel.epoch = 'replacement' }
  h.advance(100)
  assert(h.clients.values.all? { |c| c.engine.goal == nil }, 'unconfirmed goal survived new generation')
ensure
  h.close
end
puts 'PASS unified goal audio: delayed writes, missing ACK, observer ordering, invalid/duplicate/stale points, fallback, outage and recovery'
