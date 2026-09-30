require_relative "../../support/audio_ball_native_keys"

aliases = {0x26 => 'up', 0x57 => 'up', 0x25 => 'left', 0x44 => 'left', 0x28 => 'down', 0x53 => 'down'}
cases = %w[Alice Bob].product([1, 2, 3, 4, 5], aliases.to_a)
cases.each do |native, level, (code, shot)|
  h = AudioBallNativeKeys.new(native: native, level: level)
  h.approach(shot, GameRoomAudioBall::Engine::INITIAL_DURATION[level - 1] * 4.0 / GameRoomAudioBall::Engine::WIDTH)
  h.tap(code); h.advance
  assert(!EltenAPI::KeyboardState.held?(code), 'early tap test did not release the key')
  assert(h.clients[native].engine.phase == :flying, 'early lane tap caught outside the two-step range')
  h.advance(30)
  side = h.players.index(native)
  assert(h.clients.values.all? { |client| client.engine.phase == :waiting && client.engine.holder == side },
    'an early tap released before contact did not keep the selected lane through peer delivery')
  h.close
end
puts "PASS Audio Ball flight lane: #{cases.length} native tap/release cases, both seats, all aliases and levels"

h = AudioBallNativeKeys.new
h.approach('up', 0.06)
h.tap(0x26); h.tap(0x28); h.advance(seconds: 0.008)
assert(h.clients['Bob'].engine.phase == :flying,
  'an earlier matching queued command overrode the latest wrong lane at contact')
h.advance(seconds: 0.008)
h.tap(0x26); h.advance(seconds: 0.008)
assert(h.clients['Bob'].engine.holder == 1, 'changing back to the matching lane did not catch inside two steps')
h.close
puts 'PASS Audio Ball flight lane: only the latest accepted command decides contact'

[0, 1].each do |bot_side|
  bot_name = GameRoomParticipants.bot_id(20, 1)
  players = bot_side.zero? ? [bot_name, 'Alice'] : ['Alice', bot_name]
  h = AudioBallHarness.new(players: players, viewers: ['Alice'], server: bot_side)
  h.advance(12)
  200.times do
    break if h.clients['Alice'].engine.phase == :flying
    h.advance
  end
  engine = h.clients['Alice'].engine
  shot = engine.shot
  assert(shot, 'bot did not serve in the lane integration setup')
  bot = h.clients['Alice'].instance_variable_get(:@bots).first
  bot.define_singleton_method(:step) { |_engine, seconds:| false }
  h.press('Alice', shot)
  h.advance(110)
  assert(engine.holder == 1 - bot_side, 'human did not automatically catch the bot serve')
  h.press('Alice', 'prepare', shot)
  h.advance(110)
  assert(engine.goal == 1 - bot_side,
    'Client automatically defended a bot without a fresh incoming-flight reaction')
  h.commit
  next_bot = h.clients['Alice'].instance_variable_get(:@bots).first
  assert(next_bot.selected_lane == nil, 'new rally retained an armed bot lane')
  h.close
end
puts 'PASS Audio Ball flight lane: a bot attack cannot arm its next defense and a new rally starts unarmed'

%w[Alice Bob].product([:chat, :settings, :network, :modified, :refocus]).each do |native, mode|
  h = AudioBallNativeKeys.new(native: native)
  h.approach('up', 0.3)
  h.tap(0x26); h.advance
  client = h.clients[native]
  h.keys(mode == :modified ? [0x11, 0x28] : [0x28])
  case mode
  when :chat
    h.forms[native].index = 1
    h.advance(30)
  when :settings
    client.instance_variable_get(:@program).define_singleton_method(:show_audio_ball_settings) do |tick:, **_options|
      tick.call
      h.advance(30)
    end
    client.show_settings
  when :network
    ui = client.network_task_ui(ui: Object.new, title: 'Saving', show_after: 100.0, cancellation_token: nil)
    30.times do
      h.advance(names: h.players - [native])
      $activecontrols = [h.field]
      ui.update
    end
    ui.close
    $activecontrols = nil
  when :refocus
    h.poll_keys
    h.field.blur
    h.field.focus
    h.advance(30)
  else
    h.advance(30)
  end
  assert(client.engine.phase == :waiting && client.engine.holder == h.players.index(native),
    "#{native}/#{mode}: UI input changed or disabled the previously selected lane")
  h.keys([]); h.advance
  h.close
end
puts 'PASS Audio Ball flight lane: chat, Ctrl+P, network progress, modifiers and refocus preserve automatic defense on both seats'

%w[Alice Bob].each do |native|
  h = AudioBallNativeKeys.new(native: native)
  h.approach('up', 0.3)
  h.tap(0x26); h.advance
  h.network['alice'].missing = ['bob']
  h.advance(5)
  assert(h.clients.values.all?(&:paused), 'network pause setup did not stop both seats')
  positions = h.clients.transform_values { |client| client.engine.position }
  h.tap(0x28); h.advance(10)
  assert(h.clients.all? { |name, client| positions[name] == client.engine.position }, 'network pause moved the ball')
  h.network['alice'].missing = []
  h.advance(40)
  assert(h.clients[native].engine.holder == h.players.index(native), 'paused input changed the lane or resume lost the previous selection')
  h.close
end
puts 'PASS Audio Ball flight lane: genuine network pause freezes physics and ignores lane changes'

h = AudioBallHarness.new(options: {'sets_to_win' => 2})
h.advance(12)
h.points_to_win.times do
  h.win_point('Alice')
  h.advance_for(5.8)
end
assert(h.replay.state[:set_number] == 2, 'flight arming setup did not reach a new set')
h.press('Bob', 'prepare', 'up')
h.advance(100)
assert(h.clients['Alice'].engine.goal == 1, 'a previous defense or attack lane survived into a new set')
h.close

h = AudioBallHarness.new
h.advance(12)
h.press('Alice', 'prepare', 'left')
h.advance(100)
assert(h.clients['Bob'].engine.goal == 0, 'new client inherited the previous match lane')
h.close
puts 'PASS Audio Ball flight lane: points, sets and a new match cannot inherit an armed defense'
