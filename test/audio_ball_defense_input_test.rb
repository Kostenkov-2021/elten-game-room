require_relative 'support/audio_ball_native_keys'

cases = %w[Alice Bob].product([1, 2, 3, 4, 5], {0x26 => 'up', 0x57 => 'up', 0x25 => 'left', 0x44 => 'left', 0x28 => 'down', 0x53 => 'down'}.to_a)
cases.each do |native, level, (code, shot)|
  h = AudioBallNativeKeys.new(native: native, level: level)
  side = h.players.index(native)
  h.approach(shot, GameRoomAudioBall::Engine::INITIAL_DURATION[level - 1] * 4.0 / GameRoomAudioBall::Engine::WIDTH)
  engine = h.clients[native].engine
  h.keys([code]); h.advance
  assert(engine.phase == :flying, 'held key defended before the two-step range')
  h.advance(25)
  assert(EltenAPI::KeyboardState.held?(code) && !EltenAPI::KeyboardState.pressed?(code), 'test did not exercise a held key without repeat events')
  assert(engine.holder == side && engine.goal == nil,
    "holding matching key #{code} through the legal defense range always conceded the ball")
  h.keys([code, 0x27]); h.advance
  assert(engine.phase == :prepared, 'defender cannot prepare while releasing its defense key')
  h.advance(10)
  assert(engine.phase == :prepared, 'held defense key automatically attacked after preparation')
  h.keys([]); h.advance
  h.keys([code]); h.advance
  assert(engine.phase == :flying && engine.receiver == 1 - side, 'fresh attack did not work after held defense and preparation')
  h.close
end
puts "PASS native Audio Ball held defenses: #{cases.length} cases, both sides, all levels and six aliases, exact range, separate preparation and fresh attack"

h = AudioBallNativeKeys.new
h.approach('left', 0.024)
assert(h.clients['Bob'].engine.position < 2.0, 'tap setup is not in the legal defense range')
h.keys([0x25]); h.advance(seconds: 0.04)
assert(h.clients['Bob'].engine.holder == 1 && h.clients['Bob'].engine.goal == nil,
  'physics discarded a matching press already sampled inside the defense range')
h.close
puts 'PASS native Audio Ball short defense is processed before advancing beyond the end of the frame'

short_cases = %w[Bob Alice].product(
  {0x25 => 'left', 0x44 => 'left', 0x28 => 'down', 0x53 => 'down', 0x26 => 'up', 0x57 => 'up'}.to_a,
  [0.04, 0.008])
short_cases.each do |native, (code, shot), seconds|
  h = AudioBallNativeKeys.new(native: native)
  side = h.players.index(native)
  wrong_code = shot == 'down' ? 0x25 : 0x28
  h.approach(shot, 0.080)
  h.keys([wrong_code]); h.advance
  h.advance while h.remaining > 0.024
  assert(h.remaining > 0.0, 'short tap setup already missed the ball')
  h.tap(code); h.advance(seconds: seconds)
  assert(EltenAPI::KeyboardState.pressed?(code) && !EltenAPI::KeyboardState.held?(code) &&
    EltenAPI::KeyboardState.held?(wrong_code) && !EltenAPI::KeyboardState.pressed?(wrong_code),
    'short tap setup did not sample a released fresh key beside an older held wrong key')
  engine = h.clients[native].engine
  # A released correction now yields to the previous still-held key. This is
  # the intentional hold-fallback contract, not a lost short keydown.
  assert(h.clients[native].instance_variable_get(:@selected_lane) == (shot == 'down' ? 'left' : 'down'),
    "#{native}, key=#{code}, frame=#{seconds}: released correction did not restore the held key")
  h.advance(5)
  assert(h.clients.values.all? { |client| client.engine.goal == 1 - side },
    'the single selected wrong held defence did not produce the same miss at both peers')
  h.close
end
puts "PASS native Audio Ball released correction restores older held key: #{short_cases.length} cases, both sides, six aliases, short and same-frame-miss intervals"

%w[Alice Bob].product(%w[left down]).each do |native, shot|
  h = AudioBallNativeKeys.new(native: native)
  h.approach(shot, 0.2)
  h.keys([0x25, 0x28]); h.advance
  assert(h.clients[native].engine.phase == :flying, 'multiple held keys defended outside the physical range')
  h.advance(30)
  engine = h.clients[native].engine
  assert(shot == 'down' ? engine.holder == h.players.index(native) : engine.goal == 1 - h.players.index(native),
    'multiple directions did not keep the latest accepted lane (down)')
  h.close
end
puts 'PASS native Audio Ball multiple directions select the latest lane, not the matching lane'

[:released, :wrong, :modified, :chat].each do |kind|
  h = AudioBallNativeKeys.new
  h.approach('up', 0.2)
  h.keys(kind == :wrong ? [0x28] : kind == :modified ? [0x10, 0x26] : [0x26])
  h.forms['Bob'].index = 1 if kind == :chat
  h.advance
  h.keys([]) if kind == :released
  h.advance(30)
  engine = h.clients['Bob'].engine
  assert(kind == :released ? engine.holder == 1 : engine.goal == 0,
    "#{kind}: released selection was lost or invalid input selected a lane")
  h.close
end
puts 'PASS native Audio Ball input isolation: release preserves lane; wrong lane, modifier and chat cannot catch'

[:save, :error].each do |exit_kind|
  h = AudioBallNativeKeys.new
  h.approach('up', 0.2)
  client = h.clients['Bob']
  client.instance_variable_get(:@program).define_singleton_method(:show_audio_ball_settings) do |**_options|
    h.keys([0x26])
    h.poll_keys
    raise 'injected modal error' if exit_kind == :error
  end
  begin
    client.show_settings
  rescue RuntimeError => error
    raise unless exit_kind == :error && error.message == 'injected modal error'
  end
  h.advance(30)
  assert(client.engine.goal == 0, "#{exit_kind}: a navigation key held only inside settings defended after the dialog closed")
  h.close
end
puts 'PASS native Audio Ball modal exit: held navigation keys require release, also after a failed settings dialog'
