require_relative "../../support/host_source"
host_source = EltenTestHost.root
require File.join(host_source, 'src/eapi/speech.rb')
require_relative "../../support/pong_client"

def advance_to(h, target, names: h.clients.keys)
  while h.now < target
    h.now = [h.now + 0.016, target].min
    names.each { |name| h.clients.fetch(name).frame }
  end
end

# An indexed output that NEVER completes. Do not execute the final marker:
# the real NVDA addon can omit it for the empty trailing SpeechSequence text.
def stalled_speech(client, indexed: true)
  messages = []
  client.define_singleton_method(:speech_indexes_supported?) { indexed }
  client.define_singleton_method(:current_speechsequence) { @test_sequence }
  client.define_singleton_method(:speak) do |text|
    messages << text
    @test_sequence = text.is_a?(EltenAPI::SpeechSequence) ? text : nil
  end
  messages
end

[%w[Alice Bob Carol Dave], %w[Bob Carol Dave Erin]].each do |players|
  h = PongHarness.new(players: players, options: {'team_size' => 2})
  begin
    messages = h.clients.to_h { |name, client| [name, stalled_speech(client, indexed: name != 'Carol')] }
    advance_to(h, 8.0)
    assert(h.clients.values.none?(&:paused), 'A missing speech completion still blocks doubles')
    assert(messages.values.flatten.all? { |text| text.is_a?(String) }, 'Pairing still requests indexed speech')
    assert(h.network.values.all? { |channel| channel.resets.zero? }, 'Speech required reconnect to unlock play')
    assert(h.clients.values.all? { |client| client.engine.turn.zero? }, 'Readiness served without a fresh press')
    h.network.each_value { |channel| channel.epoch = 'replacement' }
    count = messages.transform_values { |items| items.grep(/will serve against/).length }
    advance_to(h, 16.0)
    assert(h.clients.values.none?(&:paused), 'Reconnect retained a speech barrier')
    assert(messages.transform_values { |items| items.grep(/will serve against/).length } == count,
      'Reconnect repeated an already announced service pair')
  ensure
    h.close
  end
end

# Both serves in each block, with and without an early goal preview, use the
# Single score + 2.7 second deadline. The pairing adds no second countdown.
[false, true].each do |preview|
  [1, 2].each do |rally|
    single = PongHarness.new
    doubles = PongHarness.new(players: %w[Alice Bob Carol Dave], options: {'team_size' => 2})
    begin
      [single, doubles].each do |h|
        messages = h.clients.to_h { |name, client| [name, stalled_speech(client)] }
        advance_to(h, 10.0)
        (rally - 1).times { |i| h.accept_point("#{i}:0") }
        before = h.replay
        h.clients.each_value { |client| client.send(:preview_goal, 0) } if preview
        h.accept_point("#{rally - 1}:0")
        if preview
          h.clients.each { |name, client| client.event({'action' => 'pong_point'}, before, h.replay, name, h.repository) }
        end
        h.clients.each_value { |client| assert((client.send(:rally_state).ready_at - 15.7).abs < 0.000001,
          'Post-score pause is not the ordinary 2.7 seconds') }
        server = h.players[h.clients['Alice'].engine.server]
        advance_to(h, 15.4)
        assert(h.clients.values.all?(&:paused), 'Service unlocked before the ordinary deadline')
        h.press(server)
        h.surfaces[server].controls['hit'] = true
        advance_to(h, 15.69)
        assert(h.clients.values.all?(&:paused), 'Announcement shortened the countdown')
        advance_to(h, 16.0)
        assert(h.clients.values.none?(&:paused), 'Announcement added an extra pause after 2.7 seconds')
        assert(h.clients['Alice'].engine.turn.zero?, 'A press held through the pause served automatically')
        if h == doubles
          expected = rally.even? ? 2 : 1
          assert(messages.values.all? { |items| items.grep(/will serve against/).length == expected },
            'Pairing must be announced once per change, not again on the second serve')
        end
        h.surfaces[server].controls['hit'] = false
        h.advance(2)
        h.press(server)
        h.advance(8)
        assert(h.players.all? { |name| h.clients[name].engine.turn == 1 }, 'Fresh serve failed after the fixed pause')
      end
    ensure
      single.close
      doubles.close
    end
  end
end

# No speech barrier must not mean no synchronization: missing participants
# still prevent play, then join without anyone having to stop their speech.
h = PongHarness.new(players: %w[Alice Bob Carol Dave], options: {'team_size' => 2})
begin
  h.clients.each_value { |client| stalled_speech(client) }
  advance_to(h, 8.0, names: %w[Alice Bob Carol Watcher])
  assert(h.clients['Alice'].paused && h.clients['Alice'].engine.turn.zero?, 'Absent player no longer blocks startup')
  advance_to(h, 16.0)
  assert(h.clients.values.none?(&:paused), 'Late player did not release synchronized startup')
ensure
  h.close
end

puts 'PASS fixed serve pause: missing speech completion, fallback, observing owner, reconnect, both serves, preview, held keys and late player'
