require_relative '../../support/pong_client'
require_relative '../../support/pong_audio'

class ContactClientAudio < GameRoomPong::Audio
  attr_accessor :trace
  def feedback(snapshot, **options)
    kind = snapshot['fx'].last&.[](1)
    @trace << [:contact, snapshot['b'].dup, options.dup] if %w[serve hit shield_hit].include?(kind)
    super
  end
  def play_effect(kind, side, *args)
    @trace << [:effect, kind, side]
    super
  end
end

[%w[Alice Bob], %w[Alice Bob Carol Dave]].each do |players|
  options = players.length == 4 ? {'team_size' => 2, 'team_seats' => [0, 0, 1, 1]} : {}
  h = PongHarness.new(players: players, options: options)
  begin
    traces, audios = {}, {}
    h.clients.each do |name, client|
      client.define_singleton_method(:first_server) { 0 }
      client.send(:reset_rally)
      trace = traces[name] = []
      audio = audios[name] = ContactClientAudio.new(PongAudioProgram.new, clock: -> { h.now })
      audio.trace = trace
      audio.prepare_players(players.length)
      audio.load
      client.instance_variable_set(:@audio, audio)
    end
    h.advance(220)
    assert(h.clients.values.none?(&:paused), 'fixture failed to become ready')
    h.clients.each do |name, client|
      # The first channel epoch rebuilds the rally engine; instrument that
      # current object, not the provisional engine created before handshake.
      trace = traces[name]
      client.engine.define_singleton_method(:step) do |*args, **kwargs|
        trace << [:step, ball.dup]
        super(*args, **kwargs)
      end
    end
    traces.each_value(&:clear)
    h.press(players.first)
    h.advance(4)
    h.clients.each do |name, client|
      effects = traces[name].select { |row| row[0] == :effect && row[1] == 'serve' }
      assert(effects.length == 1, "#{players.length}/#{name}: serve played #{effects.length} times")
      next if name == players.first || name == 'Watcher'
      contact_at = traces[name].index { |row| row[0] == :contact }
      step_at = traces[name].index { |row| row[0] == :step }
      assert(contact_at && step_at && contact_at < step_at, "#{name}: received serve audio waited for physics: #{traces[name].inspect}")
    end
    receiver = players[h.clients[players.first].engine.rotation.hitter(1)]
    actor = h.clients[receiver]
    side = players.index(receiver)
    actor.engine.move_to(side, 1.0, silent: true)
    actor.engine.ball.merge!('x' => 4.5, 'y' => 19.0, 'speed' => 0.4, 'dy' => 1)
    traces.each_value(&:clear)
    h.press(receiver)
    # Process the hitter first so all other clients receive on the next frame.
    h.advance(1, names: [receiver])
    names = h.clients.keys - [receiver]
    h.advance(4, names: names)
    names.each do |name|
      effects = traces[name].select { |row| row[0] == :effect && row[1] == 'hit' }
      assert(effects.length == 1, "#{players.length}/#{name}: missing/duplicate accepted return")
      next if name == 'Watcher'
      contact_at = traces[name].index { |row| row[0] == :contact }
      step_at = traces[name].index { |row| row[0] == :step }
      assert(contact_at && step_at && contact_at < step_at, 'remote hit audio waited for physics')
      state = traces[name][contact_at][1]
      assert(state['x'] == 4.5 && state['y'] == 20.0, 'sound skipped the accepted return position')
    end
    host = h.clients[players.first]
    contact_count = traces[players.first].count { |row| row[0] == :contact }
    effect_count = traces[players.first].count { |row| row[0] == :effect && row[1] == 'hit' }
    packet = JSON.parse(h.network[receiver.downcase].event_sent.last)
    # Duplicate, invalid actor and a future action must not produce sound.
    h.network['alice'].event_inbox << [receiver.downcase, packet]
    future = Marshal.load(Marshal.dump(packet))
    future['d']['turn'] += 2
    h.network['alice'].event_inbox << ['watcher', future]
    h.network['alice'].event_inbox << [receiver.downcase, future]
    h.advance(4)
    assert(traces[players.first].count { |row| row[0] == :contact } == contact_count,
      'invalid/duplicate/future action started contact audio')
    assert(traces[players.first].count { |row| row[0] == :effect && row[1] == 'hit' } == effect_count,
      'end-of-frame update restarted the remote hit')
    assert(traces['Watcher'].none? { |row| row[0] == :contact }, 'remote spectator used a playable engine timeline')
  ensure
    h.close
  end
end

puts 'PASS Pong client contact timing: accepted relay returns before physics, one effect, singles/doubles, actor/order validation and snapshot-only observers'
