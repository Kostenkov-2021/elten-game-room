require 'digest'
require_relative 'engine'
require_relative 'defense_input'
require_relative 'bot'
require_relative 'audio'
require_relative '../realtime/event_channel'
require_relative '../realtime/timer'
require_relative '../realtime/task_ui'
require_relative '../realtime/table_control'

require_relative "../game_room_localization"

module GameRoomAudioBall
  using GameRoomLocalization::Translations
  class Client
    include GameRoomRealtime::TableControl
    SEND_INTERVAL = 0.04
    POINT_PAUSE = 5.7
    SET_PAUSE = 5.0
    STREAM_TIMEOUT = 4.0
    attr_reader :engine, :snapshot, :paused

    def initialize(program, game, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, channel_factory: nil, audio: nil, transport: nil)
      @program, @game, @clock = program, game, clock
      @activity_transport = transport
      @channel_factory = channel_factory || ->(**args) { GameRoomRealtime::EventChannel.new(**args) }
      @audio = audio || Audio.new(program, clock: clock)
      @paused, @closed = true, false
      @peers, @connections, @deferred = {}, {}, []
      @sequence = @event_sequence = 0
      @next_send = 0.0
      @last_reconnect = -30.0
      @selected_lane = nil
      @defense_input = DefenseInput.new
    end

    def bind_screen(session_id:, table_id:, owner:, viewer:, members:)
      @activity_table, @activity_session = table_id, session_id
      @owner, @viewer = owner.to_s, viewer.to_s
      @connection_started = @clock.call
      @match = Digest::SHA256.hexdigest("GameRoom:audio_ball:#{table_id}:#{session_id}")[0, 24]
      @base_match, @members_provider = @match, members
      @channel = @channel_factory.call(program: @program, match: @match, owner: @owner,
        viewer: @viewer, clock: @clock, members: members)
      @channel.enable_events('audio-ball-peer-2', routing: :peers)
    end

    def start
      register_ping_channel
      @audio.load
      true
    end

    def host?; @owner.casecmp?(@viewer); end
    def refresh_due?; false; end
    def context_data; {'audio_ball_point' => @pending_point}; end
    def action(_selection, _replay, _viewer); false; end
    def error(_status); end
    def automatic_error(_status); end
    def after_events(replay, viewer, context:); before_wait(replay, viewer); end

    def before_wait(replay, viewer)
      @channel.configure_p2p(replay.state[:options])
      changed = !@replay || @replay.state.values_at(:rally, :server) != replay.state.values_at(:rally, :server)
      @replay, @players = replay, replay.players
      @side = @players.index { |player| player.to_s.casecmp?(viewer.to_s) }
      @side = nil if bot_seat?(viewer)
      @required = @players.reject { |player| bot_seat?(player) || player.to_s.casecmp?(@viewer) }
      @channel.enable_events('audio-ball-peer-2', routing: :peers)
      @channel.required_members = (@required + [@owner]).uniq
      reset_rally if changed
      if replay.finished?
        @paused = true
        detach_view
        unregister_ping_channel
        @channel.close
      end
    end

    def event(event, before, after, viewer, _repository)
      return unless event['action'] == 'audio_ball_point' && before && after
      rally = after.state[:rally]
      return unless rally == before.state[:rally] + 1 && rally > @announced_rally.to_i
      @announced_rally = rally
      return if @replay && rally < @replay.state[:rally]
      result = after.state[:last_point]
      return unless result
      side = after.players.index { |player| player.to_s.casecmp?(viewer.to_s) }
      preview = @goal_preview if @goal_preview && @goal_preview[:rally] == before.state[:rally] &&
        @goal_preview[:winner] == result[:winner]
      @audio.point(result[:scores], sets: after.state[:sets], set_finished: result[:set_finished],
        winner: result[:winner], viewer: side, finished: after.finished?, goal_at: preview && preview[:at])
      @ready_at = point_ready_at(result)
      @goal_preview = nil
    end

    def presents_game_event?(event); event['action'] == 'audio_ball_point' && presents_point?; end
    def presents_game_result?(replay); replay.finished? && replay.state[:rally] == @announced_rally && presents_point?; end

    def attach_view(form, surface)
      return if @form.equal?(form) && @surface.equal?(surface) && @timer && @replay && !@replay.finished?
      detach_view
      return unless surface.respond_to?(:present) && @replay && !@replay.finished?
      @form, @surface = form, surface
      # A quiet view replacement keeps the form's focus, but activecontrols
      # still describes the previous native frame. Rebind capture to the new
      # selected field now; actual input keeps the stricter active-frame guard.
      @surface.activate_input if @surface.respond_to?(:activate_input) && @surface.input_selected?(@form)
      @surface.on_audio_ball_command = method(:local_command) if @surface.respond_to?(:on_audio_ball_command=)
      @timer = GameRoomRealtime::Timer.new(clock: @clock) { frame }
      @form.add_timer(@timer)
      @form.retain_binding_timer(@timer) if @form.respond_to?(:retain_binding_timer)
      present
    end

    def detach_view
      @timer&.stop
      @defense_input.forget_held
      @surface.deactivate_input if @surface.respond_to?(:deactivate_input)
      @surface.on_audio_ball_command = nil if @surface.respond_to?(:on_audio_ball_command=)
      @form.delete_timer(@timer) if @form && @timer
      @timer = @surface = @form = nil
      @audio.update(@snapshot, viewer: @side || 0, paused: true) if @snapshot
    end

    def tick
      return if @closed
      @audio.tick if @audio.respond_to?(:tick)
      return if !@replay || @replay.finished?
      connected = @connected || @channel.connected?
      @channel.tick
      @connected = @channel.connected?
      if connected && !@connected && !host? && @side != nil
        @resync_requested, @paused = true, true
      end
    end

    def frame
      return if @closed || !@replay || @replay.finished?
      return if @control_ready == false
      input_flight = incoming_flight
      tick
      now = @clock.call
      synchronize_epoch
      receive_packets(now)
      receive_events
      check_connection(now)
      healthy = healthy?(now)
      active = healthy && local_ready?(now)
      playable = active && !@paused
      elapsed = @last_frame && !@paused && active && !@clock_reset ? [now - @last_frame, 0.0].max : 0.0
      @clock_reset = false
      @last_frame, @paused = now, !active
      commands = @surface ? @surface.input(@form) : []
      allowed_input = playable && @side != nil && !@network_wait && !@settings_open
      flight = incoming_flight
      @selected_lane = @defense_input.update(flight: flight,
        enabled: allowed_input && input_flight && input_flight == flight,
        input: (@surface.defense_input if @surface.respond_to?(:defense_input)), commands: commands)
      @selected_flight = @selected_lane ? flight : nil
      if active
        announce_set
        advance_engine(elapsed)
        commands.each do |command|
          next unless allowed_input && @engine.phase != :flying
          drain_transitions if @engine.press(@side, command)
        end
      end
      @snapshot = @engine&.snapshot
      send_state(now, healthy)
      agree_point(now) if host? && healthy
      present
    end

    def network_task_ui(**options)
      GameRoomRealtime::TaskUI.new(**options, clock: @clock, tick: -> {
        if GameRoomRealtime::TaskUI.updates_form?(options[:ui], @form)
          # The owned form's existing timer advances the client once.
        else
          begin
            @network_wait = true
            frame
          ensure
            @network_wait = false
          end
        end
      })
    end

    def show_settings
      return if @settings_open || @closed
      opened_here = true
      @settings_open = true
      @program.send(:show_audio_ball_settings, tick: -> { frame }, clock: @clock)
    ensure
      if opened_here
        @settings_open = false
        @surface.clear_input if @surface.respond_to?(:clear_input)
        @audio.refresh_preferences if @audio.respond_to?(:refresh_preferences)
      end
    end

    def close
      return if @closed
      @closed = true
      unregister_ping_channel
      detach_view
      @channel&.close
      @audio.close
    end

    private

    # Control replacement repeats only the unfinished rally. Audio Ball owns
    # its connection and input state; the table layer knows no physics fields.
    def reset_table_control
      @defense_input.reset
      @connection_started = @clock.call
      @epoch = nil
      @peers, @connections, @deferred = {}, {}, []
      @sequence = @event_sequence = 0
      @pending_point = @goal_preview = @replay = nil
      @paused = true
      @surface.clear_input if @surface&.respond_to?(:clear_input)
    end

    def presents_point?
      !@audio.respond_to?(:presents_point) || @audio.presents_point
    end

    def reset_rally
      @defense_input.reset
      @selected_lane = @selected_flight = nil
      server = @replay.state[:server]
      @engine = server == nil ? nil : Engine.new(level: @replay.state[:options]['difficulty'], server: server)
      @snapshot = @engine&.snapshot
      @observer_synced = false
      @observer_audio_floor = @last_audio_transition = nil
      bot_sides = host? ? @players.each_index.select { |side| bot_seat?(@players[side]) } : []
      @controlled = ([@side].compact + bot_sides).uniq
      seed = Digest::SHA256.hexdigest("#{@match}:#{@epoch}:#{@replay.state[:rally]}")[0, 12].to_i(16)
      @bots = bot_sides.map do |side|
        Bot.new(side, level: @replay.state[:options]['difficulty'], rng: Random.new(seed + side))
      end
      @pending_point = @point_reason = @warning_key = nil
      @disagreements = {}
      result = @replay.state[:last_point]
      @ready_at = result ? point_ready_at(result) : @clock.call
      @last_frame = nil
      @paused = true
      @next_send = 0.0
      @audio.reset
    end

    def synchronize_epoch
      return unless @channel.epoch && @channel.epoch != @epoch
      first_local_connection = !@epoch && local_match?
      @epoch = @channel.epoch
      @recovering = false
      @resync_requested = false
      @connection_started = @clock.call
      @connections.clear
      @peers.clear
      @sequence = @event_sequence = 0
      @deferred.clear
      reset_rally unless first_local_connection || @pending_point
    end

    def packet_valid?(packet, kind)
      packet.is_a?(Hash) && packet['m'] == @match && packet['e'] == @epoch &&
        packet['v'] == GameRoomRealtime::Protocol::VERSION && packet['k'] == kind &&
        [packet['n'], packet['a']].all? { |number| number.is_a?(Integer) && number.between?(0, GameRoomRealtime::Protocol::MAX_SEQUENCE) } && packet['d'].is_a?(Hash)
    end

    def receive_packets(now)
      @channel.take_packets.each do |sender, packet|
        name = sender.to_s.downcase
        next unless host? ? @required.any? { |player| player.to_s.casecmp?(name) } : @owner.casecmp?(name)
        next unless packet_valid?(packet, host? ? 'input' : 'state')
        body = packet['d']
        next unless body['r'].is_a?(Integer) && (body['r'] - @replay.state[:rally]).abs <= 1 &&
          body['turn'].is_a?(Integer) && body['turn'].between?(0, 2**31 - 1) &&
          [nil, 0, 1].include?(body['goal']) && [true, false].include?(body['ready']) &&
          (!body.key?('resync') || [true, false].include?(body['resync']))
        connection = (@connections[name] ||= GameRoomRealtime::PeerState.new)
        next unless connection.receive(packet, now: now, last_sent: @sequence)
        next unless body['r'] == @replay.state[:rally]
        peer = (@peers[name] ||= GameRoomRealtime::PeerState.new)
        next unless peer.receive(packet, now: now, last_sent: @sequence)
        if !host? && @side == nil && @engine && body['state'].is_a?(Hash) && body['turn'] >= @engine.turn
          state = body['state']
          next unless state['server'] == @replay.state[:server] && state['level'] == @replay.state[:options]['difficulty'] &&
            state['turn'] == body['turn'] && state['goal'] == body['goal']
          if @engine.restore(state)
            @observer_audio_floor = @engine.turn unless @observer_synced
            @observer_synced = true
            @recovering = false if @channel.connected?
          end
        end
      end
    end

    def receive_events
      return unless @engine
      @channel.take_events.each do |sender, packet|
        next if !host? && @side == nil && !@observer_synced
        next unless packet_valid?(packet, 'event')
        data = packet['d']
        next unless valid_event?(data) && (data['r'] - @replay.state[:rally]).between?(0, 1)
        player = @players[data['side']]
        author = data['action'] == 'point' || bot_seat?(player) ? @owner : player.to_s
        next unless author.casecmp?(sender.to_s) && !sender.to_s.casecmp?(@viewer)
        next if data['action'] == 'warn' && bot_seat?(player)
        next if @deferred.include?(data)
        base_turn = data['r'] == @replay.state[:rally] ? @engine.turn : 0
        if data['turn'] > base_turn + GameRoomRealtime::EventChannel::LIMIT || @deferred.length >= GameRoomRealtime::EventChannel::LIMIT
          recover('AudioBallActionGap')
          break
        end
        @deferred << data
      end
      @deferred.sort_by! { |data| [data['r'], data['turn'], %w[warn point].include?(data['action']) ? 1 : 0] }
      @deferred.delete_if do |data|
        next true if data['r'] < @replay.state[:rally]
        next false if data['r'] > @replay.state[:rally]
        if data['action'] == 'warn'
          next false if data['turn'] > @engine.turn
          accept_warning(data)
          next true
        end
        if data['action'] == 'point'
          next false if data['turn'] > @engine.turn
          preview_goal(data['side']) if !host? && @engine.turn == data['turn'] && @engine.goal == data['side']
          next true
        end
        if data['turn'] <= @engine.turn
          # An observer may receive the owner's current snapshot before the
          # matching reliable event. Present its cue once without applying
          # the transition again or playing historical cues on initial join.
          transition_audio(data) if observer_snapshot_cue?(data)
          next true
        end
        next false if data['turn'] > @engine.turn + 1
        if @engine.apply(data.reject { |key, _| key == 'r' })
          note_play_activity if %w[hit defend].include?(data['action'])
          @clock_reset = true
          transition_audio(data)
        end
        true
      end
    end

    def valid_event?(data)
      return false unless data['r'].is_a?(Integer) && data['r'] >= 0 && data['turn'].is_a?(Integer) && data['turn'].between?(0, 2**31 - 1)
      return false unless [0, 1].include?(data['side'])
      keys = %w[r action side turn]
      case data['action']
      when 'prepare', 'point'
      when 'hit', 'defend'
        return false unless Engine::SHOTS.include?(data['shot'])
        keys << 'shot'
      when 'miss'
        if data.key?('reason')
          return false unless data['reason'] == 'timeout'
          keys << 'reason'
        end
      when 'warn'
        return false unless data['hits'].is_a?(Integer) && data['hits'].between?(0, 2**31 - 1)
        keys << 'hits'
      else
        return false
      end
      data.keys.sort == keys.sort
    end

    def recover(reason)
      @resync_requested = true if !host? && @side != nil
      return if @recovering || @clock.call - @last_reconnect < 10.0
      @last_reconnect = @clock.call
      @recovering, @paused = true, true
      @deferred.clear
      @channel.reconnect(reason: reason)
    end

    def check_connection(now)
      return if local_match? || !@engine
      names = host? ? @required : [@owner]
      expired = names.any? do |name|
        peer = @connections[name.downcase]
        received = host? ? peer&.ack_updated_at : peer&.received_at
        received ? now - received > STREAM_TIMEOUT : now - @connection_started > 10.0
      end
      recover('AudioBallStatusTimeout') if expired
      return unless host? && !@pending_point
      @required.each do |name|
        peer = @peers[name.downcase]
        if peer && peer.body['resync']
          recover('AudioBallPeerRejoined')
          next
        end
        identity = peer && [@engine.turn, @engine.goal, peer.body['turn'], peer.body['goal']]
        if !peer || !peer.fresh?(now, timeout: STREAM_TIMEOUT) || peer.body['r'] != @replay.state[:rally] ||
            (peer.body['turn'] == @engine.turn && peer.body['goal'] == @engine.goal)
          @disagreements.delete(name)
        elsif @disagreements[name]&.first != identity
          @disagreements[name] = [identity, now]
        elsif now - @disagreements[name][1] > STREAM_TIMEOUT
          recover('AudioBallActionDisagreement')
        end
      end
    end

    def healthy?(now)
      return false if @recovering || @resync_requested || (!host? && @side == nil && !@observer_synced)
      return true if local_match?
      return false unless @channel.connected? && @channel.required_members_present?
      if host?
        @required.all? do |name|
          peer = @peers[name.downcase]
          peer && peer.body['r'] == @replay.state[:rally] && peer.fresh?(now, timeout: STREAM_TIMEOUT) && peer.ack_fresh?(now, timeout: STREAM_TIMEOUT) && peer.body['ready'] && !peer.body['resync']
        end
      else
        peer = @peers[@owner.downcase]
        peer && peer.body['r'] == @replay.state[:rally] && peer.fresh?(now, timeout: STREAM_TIMEOUT) && peer.body['ready']
      end
    end

    def send_state(now, healthy)
      signature = @engine && [@engine.turn, @engine.goal, @paused]
      return unless @epoch && @engine && (now >= @next_send || signature != @sent_signature)
      @sent_signature = signature
      @next_send = now + SEND_INTERVAL
      @sequence += 1
      body = {'r' => @replay.state[:rally], 'turn' => @engine.turn, 'goal' => @engine.goal,
        'ready' => local_ready?(now) && (host? ? !!healthy : true), 'resync' => !!@resync_requested}
      body['state'] = @snapshot if host?
      ack = host? ? 0 : @connections[@owner.downcase]&.sequence.to_i
      @channel.send(GameRoomRealtime::Protocol.encode(match: @match, epoch: @epoch, sequence: @sequence,
        kind: host? ? 'state' : 'input', body: body, ack: ack))
    end

    def local_match?
      host? && @required.empty?
    end

    def incoming_flight
      [@engine, @engine.turn] if @engine && @engine.phase == :flying && @engine.receiver == @side
    end

    def advance_engine(elapsed)
      return if elapsed > STREAM_TIMEOUT
      while elapsed > 0.000001
        seconds = [elapsed, 0.008].min
        defenses = @selected_lane && @selected_flight == incoming_flight ? {@side => @selected_lane} : {}
        @bots.each do |bot|
          lane = bot.selected_lane(@engine)
          defenses[bot.side] = lane if lane
        end
        @engine.step(seconds, controlled: @controlled, defenses: defenses)
        drain_transitions
        @bots.each { |bot| bot.step(@engine, seconds: seconds); drain_transitions }
        elapsed -= seconds
      end
    end

    def drain_transitions
      while (data = @engine.take_transition)
        note_play_activity if %w[hit defend].include?(data['action'])
        transition_audio(data)
        emit_event(data)
      end
    end

    def emit_event(data)
      return if !@epoch || !@channel.connected?
      @event_sequence += 1
      queued = @channel.send_event(GameRoomRealtime::Protocol.encode(match: @match, epoch: @epoch, sequence: @event_sequence,
        kind: 'event', body: data.merge('r' => @replay.state[:rally])))
      recover('AudioBallActionNotQueued') unless queued
    end

    def local_command(command)
      return false unless command == 'hurry' && !@closed && !@paused && !@network_wait && !@settings_open && @side != nil && @engine
      data = {'action' => 'warn', 'side' => @side, 'turn' => @engine.turn, 'hits' => @engine.hits}
      return false unless accept_warning(data)
      emit_event(data)
      true
    end

    def accept_warning(data)
      return false unless data['hits'] == @engine.hits && (@engine.turn - data['turn']).between?(0, 1)
      return false unless [:waiting, :prepared].include?(@engine.phase) && data['side'] == 1 - @engine.holder
      key = [@replay.state[:rally], @engine.hits, @engine.holder]
      return false if @warning_key == key
      return false unless @engine.warn(data['side']) || (!host? && @side == nil && @engine.warning)
      @warning_key = key
      @clock_reset = true
      @audio.hurry(GameRoomParticipants.display_name(@players[@engine.holder]))
      true
    end

    def local_ready?(now)
      @engine != nil && !@pending_point && !@recovering && !@resync_requested && now >= @ready_at
    end

    def agree_point(now)
      return if @pending_point || !@engine || @engine.goal == nil
      return unless @required.all? do |name|
        peer = @peers[name.downcase]
        peer && peer.fresh?(now, timeout: STREAM_TIMEOUT) && peer.body['r'] == @replay.state[:rally] &&
          peer.body['turn'] == @engine.turn && peer.body['goal'] == @engine.goal
      end
      @pending_point = "#{@replay.state[:rally]}:#{@engine.goal}"
      @pending_point += ':timeout' if @point_reason == 'timeout'
      # Only the owner, after every human agrees, confirms the goal sound.
      # Scores and match results still wait for the accepted LiveSessions event.
      preview_goal(@engine.goal)
      emit_event('action' => 'point', 'side' => @engine.goal, 'turn' => @engine.turn)
    end

    def preview_goal(winner)
      return if @goal_preview && @goal_preview[:rally] == @replay.state[:rally]
      @goal_preview = {rally: @replay.state[:rally], winner: winner, at: @clock.call}
      @audio.goal(viewer: @side, winner: winner)
    end

    def point_ready_at(result)
      now = @clock.call
      # Keep the durable five-second set break, also enforced by replay.
      return now + SET_PAUSE if result[:set_finished]
      preview = @goal_preview if @goal_preview && @goal_preview[:rally] == @replay.state[:rally] - 1 &&
        @goal_preview[:winner] == result[:winner]
      preview ? [now, preview[:at] + 3.0].max + (POINT_PAUSE - 3.0) : now + POINT_PAUSE
    end

    def transition_audio(data)
      @point_reason = data['reason'] if data['action'] == 'miss'
      return unless %w[prepare defend].include?(data['action'])
      key = [@replay.state[:rally], data['turn'], data['action']]
      return if @last_audio_transition == key
      @last_audio_transition = key
      @audio.prepare(data['side'], viewer: @side || 0) if data['action'] == 'prepare'
      @audio.stop_ball(data['side'], viewer: @side || 0) if data['action'] == 'defend' && @audio.respond_to?(:stop_ball)
    end

    def observer_snapshot_cue?(data)
      return false if host? || @side != nil || !@observer_synced
      return false unless data['turn'] == @engine.turn && data['turn'] > @observer_audio_floor.to_i && @engine.holder == data['side']
      (data['action'] == 'prepare' && @engine.phase == :prepared) ||
        (data['action'] == 'defend' && @engine.phase == :waiting)
    end

    def announce_set
      number = @replay.state[:set_number]
      if @announced_set != number
        @announced_set = number
        @audio.announce_set(number)
      end
      service = [number, @replay.state[:rally] / 2]
      return if @announced_service == service
      @announced_service = service
      player = GameRoomParticipants.display_name(@players[@replay.state[:server]])
      text = GameRoomContent.utf8(_('%{player} serves.')) % {player: GameRoomContent.utf8(player)}
      if @audio.respond_to?(:announce)
        @audio.announce(text)
      else
        speak(text, stop: false, break_sequence: false)
      end
    end

    def present
      return unless @snapshot
      @surface.present(@snapshot, pause_status) if @surface
      @audio.update(@snapshot, viewer: @side || 0, paused: @paused)
    end

    def pause_status
      return '' unless @paused
      return _('Waiting for the point to be saved.') if @pending_point || @engine&.goal != nil
      result = @replay.state[:last_point]
      if result && @clock.call < @ready_at
        return result[:set_finished] ? _('Break between sets.') : _('Break between points.')
      end
      _('Waiting for players.')
    end
  end
end
