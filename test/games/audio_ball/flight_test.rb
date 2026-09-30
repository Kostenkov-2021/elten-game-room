require_relative "../../support/audio_ball_native_keys"

aliases = {0x26 => 'up', 0x57 => 'up', 0x25 => 'left', 0x44 => 'left', 0x28 => 'down', 0x53 => 'down'}
%w[Alice Bob].product(aliases.to_a).each do |native, (code, shot)|
  h = AudioBallNativeKeys.new(native: native)
  side = h.players.index(native)
  opponent = h.players[1 - side]
  h.approach(shot, 0.3)
  h.tap(code); h.advance(30)
  assert(h.clients[native].engine.holder == side, 'a released tap after the incoming hit did not catch')
  prepare_code = 0x27
  h.tap(prepare_code); h.advance
  h.tap(code); h.advance(2)
  h.press(opponent, shot)
  h.advance(110)
  assert(h.clients[native].engine.holder == 1 - side, 'opponent did not catch the return')
  h.press(opponent, 'prepare', shot)
  h.advance(110)
  assert(h.clients.values.all? { |client| client.engine.goal == 1 - side },
    "#{native}/#{code}: a second identical incoming shot was caught without a new press")
  h.close
end
puts 'PASS Audio Ball flight arming: repeated identical shots require a new press, both seats and all aliases'

%w[Alice Bob].product([false, true]).each do |native, react|
  h = AudioBallNativeKeys.new(native: native)
  side = h.players.index(native)
  opponent = h.players[1 - side]
  h.advance(12)
  h.tap(0x26)
  h.surfaces[opponent].push('prepare', 'up')
  h.advance(names: [opponent, native])
  assert(h.clients[native].engine.phase == :flying, 'same-frame remote hit did not arrive')
  h.advance
  if react
    h.tap(0x26); h.advance
  end
  h.advance(110)
  engine = h.clients[native].engine
  assert(react ? engine.holder == side : engine.goal == 1 - side,
    "#{native}/#{react}: queued pre-hit input armed a same-frame remote hit or a fresh reaction was rejected")
  h.close
end
puts 'PASS Audio Ball flight arming: remote hits cannot retroactively arm keys sampled before their delivery'

%w[Alice Bob].product(aliases.to_a, [:tap, :held]).each do |native, (code, shot), mode|
  h = AudioBallNativeKeys.new(native: native)
  side = h.players.index(native)
  opponent = h.players[1 - side]
  h.advance(12)
  mode == :held ? h.keys([code]) : h.tap(code)
  h.advance(2)
  h.press(opponent, 'prepare', shot)
  h.advance(110)
  assert(h.clients.values.all? { |client| client.engine.goal == 1 - side },
    "#{native}/#{code}/#{mode}: a pre-hit choice armed a later incoming flight")
  h.close
end
puts 'PASS Audio Ball flight arming: pre-hit taps and held keys cannot defend, both seats and all aliases'

%w[Alice Bob].product(aliases.to_a).each do |native, (code, shot)|
  h = AudioBallNativeKeys.new(native: native)
  side = h.players.index(native)
  opponent = h.players[1 - side]
  h.approach(shot, 0.3)
  h.keys([code]); h.advance(30)
  assert(h.clients[native].engine.holder == side, 'held-carry setup did not catch the first ball')
  h.tap(0x27); h.advance
  attack_code, attack = aliases.find { |_key, lane| lane != shot }
  h.tap(attack_code); h.advance(2)
  h.press(opponent, attack)
  h.advance(110)
  h.press(opponent, 'prepare', shot)
  h.advance(110)
  assert(EltenAPI::KeyboardState.held?(code), 'carry test released the original defense key')
  assert(h.clients[native].engine.goal == 1 - side, 'holding a previous defense key armed a new flight')
  h.close
end
puts 'PASS Audio Ball flight arming: an older held defense key cannot catch a repeated incoming shot'

[0, 1].each do |side|
  bot_name = GameRoomParticipants.bot_id(20, 1)
  players = side.zero? ? ['Alice', bot_name] : [bot_name, 'Alice']
  h = AudioBallHarness.new(players: players, viewers: ['Alice'], server: 1 - side)
  rng = Object.new
  def rng.rand(limit = nil); limit ? 0 : 0.9; end
  h.clients['Alice'].instance_variable_get(:@bots).first.instance_variable_set(:@rng, rng)
  h.advance(80)
  assert(h.clients['Alice'].engine.phase == :flying, 'same-frame bot setup did not serve')
  h.press('Alice', 'up')
  h.advance(100)
  assert(h.clients['Alice'].engine.holder == side, 'same-frame bot setup did not catch')
  h.press('Alice', 'prepare', 'up')
  before = h.clients['Alice'].engine.hits
  h.advance(seconds: 3.5)
  assert(h.clients['Alice'].engine.hits == before + 1, 'bot did not return the ball inside a single frame')
  assert(h.clients['Alice'].engine.goal == 1 - side, 'a bot hit in the same frame reused the previous human defense')
  h.close
end
puts 'PASS Audio Ball flight arming: bot hits inside a physics frame invalidate the previous human selection'

%w[Alice Bob].each do |native|
  h = AudioBallNativeKeys.new(native: native)
  side = h.players.index(native)
  opponent = h.players[1 - side]
  h.approach('up', 0.3)
  h.tap(0x26); h.advance
  old_turn = h.clients[native].engine.turn
  h.network.each_value { |channel| channel.epoch = 'replacement-flight' }
  h.advance(12)
  assert(h.clients.values.all? { |client| client.engine.phase == :waiting && !client.paused },
    'flight recovery did not restart a common rally')
  h.press(opponent, 'prepare', 'up')
  h.advance(2)
  assert(h.clients[native].engine.turn == old_turn, 'recovery did not exercise a repeated flight turn number')
  h.advance(110)
  assert(h.clients[native].engine.goal == 1 - side, 'recovery reused the old generation defense at the same turn')
  h.close
end
puts 'PASS Audio Ball flight arming: recovery invalidates the old selection even when flight turn numbers repeat'

bot_name = GameRoomParticipants.bot_id(20, 1)
h = AudioBallHarness.new(players: ['Alice', bot_name], viewers: ['Alice'], server: 1, connected: false)
h.advance(80)
engine = h.clients['Alice'].engine
assert(engine.phase == :flying, 'local first-attachment setup did not serve')
h.press('Alice', engine.shot)
h.network['alice'].connected = true
h.network['alice'].epoch = 'first-local-endpoint'
h.advance(100)
assert(engine.equal?(h.clients['Alice'].engine) && engine.holder == 0,
  'the first endpoint attachment invalidated an armed defense in the same local flight')
h.close
puts 'PASS Audio Ball flight arming: first local endpoint attachment preserves the ongoing armed flight'
