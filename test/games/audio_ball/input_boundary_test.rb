require_relative "../../support/audio_ball_native_keys"

class AudioBallNativeBotBoundary < AudioBallNativeKeys
  def initialize(side:, level:)
    @native = 'Alice'
    bot = GameRoomParticipants.bot_id(20, 1)
    players = side == 0 ? [@native, bot] : [bot, @native]
    AudioBallHarness.instance_method(:initialize).bind(self).call(players: players,
      owner: @native, viewers: [@native], server: 1 - side, connected: false,
      options: {'difficulty' => level})
    @raw_keys, @key_events = [], []
    surface = GameSurfaces.build(@game.surface_spec(@replay, @native))
    @field = surface.fields.first
    @field.extend(EltenAPI::UI)
    @surfaces[@native] = surface
    @forms[@native] = Form.new([@field, EditBox.new('Chat')])
    @clients[@native].attach_view(@forms[@native], surface)
    EltenAPI::KeyboardState.reset
  end

  def advance(count = 1, seconds: 0.016, names: [@native]); super; end
end

aliases = {0x26 => 'up', 0x57 => 'up', 0x25 => 'left', 0x44 => 'left', 0x28 => 'down', 0x53 => 'down'}
count = 0
%w[Alice Bob].product([1, 2, 3, 4, 5], aliases.to_a,
  [:quick_tap, :quick_hold, :release_repress, :only_before]).each do |native, level, (code, shot), mode|
  h = AudioBallNativeKeys.new(native: native, level: level)
  begin
    side = h.players.index(native)
    opponent = h.players[1 - side]
    h.advance(12)
    if mode == :release_repress
      h.keys([code]); h.advance
    else
      h.tap(code)
    end
    h.surfaces[opponent].push('prepare', shot)
    h.advance(names: [opponent, native])
    assert(h.clients[native].engine.phase == :flying, 'incoming flight did not start')
    assert(h.clients[native].instance_variable_get(:@selected_flight).nil?, 'input before a flight armed it retroactively')
    case mode
    when :quick_tap
      h.tap(code)
    when :quick_hold
      h.keys([code])
    when :release_repress
      h.keys([])
      h.instance_variable_get(:@key_events) << [code, true]
      h.instance_variable_set(:@raw_keys, [code])
    end
    h.advance
    selected = h.clients[native].instance_variable_get(:@selected_lane)
    assert(mode == :only_before ? selected.nil? : selected == shot, 'a quick post-onset reaction was lost')
    h.advance((GameRoomAudioBall::Engine::INITIAL_DURATION[level - 1] / 0.016).ceil + 4)
    engine = h.clients[native].engine
    assert(mode == :only_before ? engine.goal == 1 - side : engine.holder == side,
      "#{native}/#{level}/#{code}/#{mode}: quick input changed the physical result")
    if mode != :only_before
      assert(h.clients.values.all? { |client| client.engine.holder == side && client.engine.goal.nil? },
        'accepted defense did not agree across the two clients')
    end
    count += 1
  ensure
    h.close
  end
end
puts "PASS Audio Ball onset boundaries: #{count} cases, both peer seats, five levels, all aliases, taps/holds/represses and no preflight arming"

# Reproduce GetAsyncKeyState seeing a new physical key after the current
# snapshot; its keydown arrives normally in the next native snapshot.
original = EltenWindow.method(:keyboard_key_held?)
count = 0
begin
  [:human, :bot].product([0, 1], [1, 2, 3, 4, 5], [:arrow, :letter]).each do |opponent, side, level, family|
    EltenWindow.define_singleton_method(:keyboard_key_held?, original)
    native = side == 0 ? 'Alice' : 'Bob'
    if opponent == :bot
      native = 'Alice'
      h = AudioBallNativeBotBoundary.new(side: side, level: level)
    else
      h = AudioBallNativeKeys.new(native: native, level: level)
      h.advance(12)
      h.press(h.players[1 - side], 'prepare', 'up')
    end
    begin
      engine = h.clients[native].engine
      500.times do
        break if engine.phase == :flying && engine.receiver == side
        h.advance
      end
      assert(engine.phase == :flying && engine.receiver == side, 'opponent did not launch a flight')
      cue = h.audios[native].calls.last
      assert(cue[0] == :update && cue[1]['phase'] == 'flying' && !cue[3], 'flight was not presented')
      keys = family == :arrow ? {'up' => 0x26, 'left' => 0x25, 'down' => 0x28} : {'up' => 0x57, 'left' => 0x44, 'down' => 0x53}
      code = keys.fetch(engine.shot)
      h.now += 0.016
      h.poll_keys
      EltenWindow.define_singleton_method(:keyboard_key_held?) { |key| key == code }
      $activecontrols = [h.field]
      h.field.update
      h.clients[native].frame
      assert(h.clients[native].instance_variable_get(:@selected_lane).nil?, 'async held invented a press before its event')
      h.keys([code]); h.advance
      assert(h.clients[native].instance_variable_get(:@selected_lane) == engine.shot, 'queued fresh down was rejected after an async held peek')
      h.advance((engine.duration / 0.016).ceil + 4)
      assert(engine.holder == side && engine.goal.nil?, "#{opponent}/#{side}/#{level}/#{family}: held defense lost")
      count += 1
    ensure
      h.close
      $activecontrols = nil
    end
  end
ensure
  EltenWindow.define_singleton_method(:keyboard_key_held?, original)
end
puts "PASS Audio Ball async-held race: #{count} cases with local real bots and peer opponents, both seats, five levels, letters/arrows"

%w[Alice Bob].product([:before_contact, :after_miss]).each do |native, timing|
  h = AudioBallNativeKeys.new(native: native)
  begin
    h.approach('up', 0.032)
    h.tap(0x28); h.advance(seconds: 0.008)
    h.tap(0x26); h.tap(0x28); h.advance(seconds: 0.008)
    # Up was tapped in the immediately preceding snapshot; native suppression
    # must not drop the final real correction, nor resurrect a finished ball.
    h.advance(10) if timing == :after_miss
    h.tap(0x26); h.advance(seconds: 0.040)
    side = h.players.index(native)
    engine = h.clients[native].engine
    assert(timing == :before_contact ? engine.holder == side : engine.goal == 1 - side,
      "#{native}/#{timing}: latest correction/contact boundary was mishandled")
  ensure
    h.close
  end
end
puts 'PASS Audio Ball last-moment correction before contact; no undo of an already recorded miss'
