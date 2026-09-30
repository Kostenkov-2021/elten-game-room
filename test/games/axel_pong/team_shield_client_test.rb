require_relative "../../support/pong_client"

class TeamShieldClientRandom
  attr_accessor :value
  def initialize; @value = 0.5; end
  def rand(*_args); @value; end
end

[[0, 0, 1, 1], [0, 1, 0, 1], [1, 0, 1, 0]].each do |teams|
  [%w[Alice Bob Carol Dave], %w[Bob Carol Dave Erin]].each do |players|
    h = PongHarness.new(players: players, options: {'team_size' => 2, 'team_seats' => teams, 'arcade' => true})
    begin
      h.advance(550)
      host = h.clients['Alice']
      random = TeamShieldClientRandom.new
      host.engine.instance_variable_set(:@rng, random)
      h.press(players[host.engine.server])
      h.advance(5)
      assert(host.engine.turn == 1, 'team shield fixture did not serve')
      winner = host.engine.rotation.hitter(1)
      members = host.engine.rotation.members(teams[winner])
      observer_snapshots = h.clients.select { |_, client| pong_remote_observer?(client) }.transform_values { |client| Marshal.load(Marshal.dump(client.snapshot)) }
      h.network.each_value { |channel| channel.drop = true }
      [:gain, :hit, :miss, :hit, :miss, :hit, :renew, :hit, :miss].each do |mode|
        turn = host.engine.turn
        seat = host.engine.rotation.hitter(turn)
        actor = h.clients[players[seat]]
        charged = [:gain, :renew].include?(mode)
        random.value = charged ? 0.01 : 0.5
        before_shields = actor.engine.shields.dup
        actor.engine.ball.merge!('x' => mode == :miss ? 1.0 : actor.engine.paddles[seat],
          'y' => teams[seat].zero? ? (mode == :miss ? 0.5 : 3.0) : (mode == :miss ? 19.5 : 17.0))
        h.press(players[seat]) unless mode == :miss
        h.advance(5)
        h.clients.each do |name, client|
          if pong_remote_observer?(client)
            assert(client.snapshot == observer_snapshots[name] && client.engine.turn.zero?, 'spectator replayed missing history during snapshot loss')
            next
          end
          assert(client.engine.turn == turn + 1 && client.engine.goal.nil?,
            "#{name}: #{mode} did not continue the team rally")
          assert(members.all? { |member| client.engine.shields[member] > 0 },
            "#{name}: #{mode} left a partner without a shield")
          assert(members.map { |member| client.engine.shields[member] }.uniq.length == 1,
            "#{name}: partner shield timers diverged")
          assert((teams.each_index.to_a - members).all? { |opponent| client.engine.shields[opponent].zero? },
            "#{name}: the opposing team received the shield")
        end
        if charged
          assert(actor.engine.shields[seat] > 600, 'team renewal did not restore ten seconds')
          assert(actor.engine.shields[seat] > before_shields[seat], 'partner renewal did not extend the existing shield')
        elsif mode == :miss
          transitions = h.network[players[seat].downcase].event_sent.map { |packet| JSON.parse(packet)['d'] }
          assert(transitions.last['action'] == 'shield_hit' && transitions.last['side'] == seat,
            'shared shield did not emit the designated participant return')
        end
      end
      h.network.each_value { |channel| channel.drop = false }
      h.advance(5)
      h.clients.each_value do |client|
        next unless pong_remote_observer?(client)
        assert(pong_presented_turn(client) == host.engine.turn, 'spectator did not recover the complete snapshot')
        assert(members.all? { |member| client.snapshot['shields'][member] > 0 }, 'recovered spectator lost team shields')
      end
      effects = h.network['alice'].event_sent.map { |packet| JSON.parse(packet)['d'] }
        .select { |event| event['action'] == 'effects' && event['renew'] }
      assert(effects.map { |event| event['side'] }.sort == members.sort,
        'fixture did not award one shield to each partner through the host')
      assert(h.network.values.reject { |channel| channel.viewer == 'alice' }.all? do |channel|
        channel.event_sent.none? { |packet| JSON.parse(packet).dig('d', 'action') == 'effects' }
      end, 'a guest rolled its own team shield')
      h.network.each_value { |channel| channel.drop = false }
      h.advance(5)
      watcher = h.clients.fetch('Watcher')
      assert(watcher.instance_variable_get(:@observer_turn) == host.engine.turn && watcher.snapshot['goal'] == host.engine.goal,
        'Spectator failed to resume authoritative snapshots')
      assert(watcher.snapshot['shields'].each_with_index.all? { |value, index| (value - host.engine.shields[index]).abs <= 5 },
        'Spectator missed the shared shield state')
    ensure
      h.close
    end
  end
end
puts 'PASS team shields across clients: both partners saved and renewed, owner-player and owner-observer, reliable effects without position packets'
