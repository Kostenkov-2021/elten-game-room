require_relative "../../support/audio_ball_native_keys"

checks, failures = 0, []
check = lambda do |name, &block|
  checks += 1
  begin
    block.call
  rescue StandardError => error
    failures << "#{name}: #{error.message}"
  end
end

%w[Alice Bob].product((1..5).to_a, [:separate_frames, :same_frame]).each do |native, level, timing|
  check.call("held fallback #{native}/#{level}/#{timing}") do
    h = AudioBallNativeKeys.new(native: native, level: level)
    begin
      h.approach('left', GameRoomAudioBall::Difficulty::PROFILES[level - 1][:duration] * 0.5)
      h.keys([0x44]); h.advance(seconds: 0.01)
      if timing == :same_frame
        h.tap(0x53); h.advance(seconds: 0.01)
      else
        h.keys([0x44, 0x53]); h.advance(seconds: 0.01)
        assert(h.clients[native].instance_variable_get(:@selected_lane) == 'down', 'new held key did not take priority')
        h.keys([0x44]); h.advance(seconds: 0.01)
      end
      assert(h.clients[native].instance_variable_get(:@selected_lane) == 'left', 'releasing S did not restore held D')
      h.keys([]); h.advance(seconds: 0.01)
      assert(h.clients[native].instance_variable_get(:@selected_lane) == 'left', 'releasing all keys lost the last active defence')
      h.advance((GameRoomAudioBall::Difficulty::PROFILES[level - 1][:duration] / 0.01).ceil, seconds: 0.01)
      side = h.players.index(native)
      assert(h.clients.values.all? { |c| c.engine.holder == side && c.engine.goal.nil? }, 'defence did not agree on both clients')
    ensure
      h.close
    end
  end
end

[:three_keys, :aliases, :three_taps, :repeat, :chat, :focus, :modified, :settings, :preflight, :next_ball, :silent_refresh, :silent_resume].each do |kind|
  check.call(kind.to_s) do
    h = AudioBallNativeKeys.new(level: 3)
    begin
      if kind == :preflight
        h.advance(12)
        h.keys([0x44]); h.advance
      end
      h.approach('left', 0.6)
      h.keys([0x44]); h.advance
      client = h.clients['Bob']
      selected = -> { client.instance_variable_get(:@selected_lane) }
      case kind
      when :three_keys
        h.keys([0x44, 0x53]); h.advance
        h.keys([0x44, 0x53, 0x57]); h.advance
        assert(selected.call == 'up', 'third key did not win')
        h.keys([0x44, 0x53]); h.advance
        assert(selected.call == 'down', 'third key release did not restore second')
        h.keys([0x44]); h.advance
        assert(selected.call == 'left', 'second key release did not restore first')
      when :aliases
        h.keys([0x44, 0x25]); h.advance
        h.keys([0x44, 0x25, 0x53]); h.advance
        h.keys([0x25, 0x53]); h.advance
        assert(selected.call == 'down', 'releasing an older alias changed the newest defence')
        h.keys([0x25]); h.advance
        assert(selected.call == 'left', 'releasing one alias removed the other held alias')
      when :three_taps
        h.keys([]); h.advance
        [0x44, 0x53, 0x44].each { |code| h.tap(code) }; h.advance
        assert(selected.call == 'left', 'real D-S-D taps were lost')
      when :repeat
        h.keys([0x44, 0x53]); h.advance
        h.instance_variable_set(:@key_events, [[0x44, :repeat]])
        h.advance
        assert(selected.call == 'down', 'D autorepeat stole priority from S')
      when :chat, :focus, :settings
        h.keys([0x44, 0x53]); h.advance
        if kind == :chat
          h.forms['Bob'].index = 1
          h.keys([0x44]); h.advance
          h.forms['Bob'].index = 0
          h.field.focus
        elsif kind == :focus
          h.field.blur
          h.keys([0x44]); h.poll_keys
          h.field.focus
        else
          client.instance_variable_set(:@settings_open, true)
          h.keys([0x44]); h.advance
          client.instance_variable_set(:@settings_open, false)
          h.surfaces['Bob'].clear_input
        end
        h.advance
        assert(selected.call == 'down', 'return from another field restored a stale held defence')
        h.keys([]); h.advance
        h.keys([0x44]); h.advance
        assert(selected.call == 'left', 'new press after returning was blocked')
      when :modified
        h.keys([0x44, 0x53]); h.advance
        h.keys([0x44, 0x53, 0x11]); h.advance
        h.keys([0x44]); h.advance
        assert(selected.call == 'down', 'Ctrl shortcut released into a held defence')
      when :preflight
        h.tap(0x53); h.advance
        assert(selected.call == 'down', 'held key from before the flight became armed')
      when :next_ball
        h.advance(60)
        assert(client.engine.holder == 1, 'first defence failed')
        h.tap(0x41); h.advance
        h.advance(3)
        assert(client.engine.phase == :prepared, 'held defence fired after preparation')
        h.tap(0x57); h.advance
        h.advance # The receiver must first hear this new flight.
        h.press('Alice', 'up')
        h.advance(120)
        assert(h.clients['Alice'].engine.holder == 0, 'opponent failed to catch the reply')
        h.press('Alice', 'prepare', 'left')
        h.advance
        assert(selected.call.nil?, 'held defence carried over to the next incoming ball')
        h.advance(120)
        assert(client.engine.goal == 0, 'a new flight was defended without a fresh press')
      when :silent_refresh
        h.keys([]); h.advance
        old = h.field
        replacement = GameSurfaces.build(h.game.surface_spec(h.replay, 'Bob'))
        h.surfaces['Bob'] = replacement
        h.forms['Bob'].fields[0] = replacement.fields.first
        h.instance_variable_set(:@field, replacement.fields.first)
        h.field.extend(EltenAPI::UI)
        $activecontrols = [old]
        client.attach_view(h.forms['Bob'], replacement)
        $activecontrols = nil
        assert(GameRoomAudioBall::Keyboard.active?, 'quiet field replacement left ordered keyboard capture detached')
        h.keys([0x44]); h.advance
        h.tap(0x53); h.advance
        assert(selected.call == 'left', 'quietly refreshed field did not restore held defence')
        h.forms['Bob'].index = 1
        client.attach_view(h.forms['Bob'], replacement)
        assert(!GameRoomAudioBall::Keyboard.active?, 'view reattachment activated the keyboard while chat was selected')
      when :silent_resume
        h.keys([]); h.advance
        # loop_update may report blur during a passive task even though the
        # game stays selected. Quiet Form#wait resumes without calling focus.
        h.field.blur
        assert(!GameRoomAudioBall::Keyboard.active?, 'blur did not stop capture')
        h.advance
        assert(GameRoomAudioBall::Keyboard.active?, 'quiet native update did not reacquire capture')
        h.keys([0x44, 0x25]); h.advance
        h.keys([0x44, 0x25, 0x53]); h.advance
        h.keys([0x25]); h.advance
        assert(selected.call == 'left', 'resumed field lost ordered alias/held selection')
      end
    ensure
      h.close
    end
  end
end

raise failures.join("\n") unless failures.empty?
puts "PASS Audio Ball held defence: #{checks} cases, both seats, five levels, ordered fallback, sticky tap and peer agreement"
