require_relative "../../support/audio_ball_native_keys"

# Exercise actual host KeyboardState/UI; only the operating-system read is fake.
class AudioBallFastInputProbe
  attr_reader :field

  def initialize
    EltenAPI::KeyboardState.reset
    @field = GameSurfaces::AudioBallField.new('Fast input')
    @field.extend(EltenAPI::UI)
    @now = 0.0
    # Enter a focused native field before delivering its first game frame.
    frame([], update: false)
    @field.focus
  end

  def state(*codes)
    bytes = "\0" * 256
    codes.each { |code| bytes.setbyte(code, 0x80) }
    bytes
  end

  def tap(code)
    [[code, true, state(code)], [code, false]]
  end

  def frame(events = [], held: [], update: true, **options)
    @now += 0.016
    result = EltenAPI::KeyboardState.update(raw_state: state(*held), events: events,
      now: @now, pressed_implies_held: false, synthesize_repeats: false, **options)
    $input_frame_serial = $input_frame_serial.to_i + 1
    $keyboard_state_frame_serial = $input_frame_serial
    $keyboard_state_frame_thread = Thread.current
    @field.update if update
    result
  end

  def input; @field.take_input; end
end

failures = []
checks = 0
check = lambda do |name, &work|
  checks += 1
  begin
    work.call
  rescue StandardError => error
    failures << "#{name}: #{error.message}"
  end
end

GameRoomAudioBall::Keyboard::KEYS.each do |code, command|
  check.call("adjacent real taps #{code}") do
    probe = AudioBallFastInputProbe.new
    4.times do
      probe.frame(probe.tap(code))
      assert(probe.input == [command], 'a released key pressed again in the next frame disappeared')
      probe.field.update
      assert(probe.input.empty?, 'one native frame was consumed twice')
    end
  end

  check.call("release/repress between snapshots #{code}") do
    probe = AudioBallFastInputProbe.new
    probe.frame([[code, true]], held: [code])
    assert(probe.input == [command], 'first held press failed')
    probe.frame([[code, false], [code, true, probe.state(code)]], held: [code])
    assert(!EltenAPI::KeyboardState.pressed?(code), 'host limitation was changed globally')
    assert(probe.input == [command], 'release and genuine repress were treated as autorepeat')
    probe.frame([[code, :repeat]], held: [code])
    assert(probe.input.empty?, 'native autorepeat became another game command')
    probe.frame([[code, true]], held: [code])
    assert(probe.input.empty?, 'duplicate down without a release became another game command')
  end

  check.call("async held ahead of queued down #{code}") do
    probe = AudioBallFastInputProbe.new
    original = EltenWindow.method(:keyboard_key_held?)
    begin
      probe.frame([], update: false)
      EltenWindow.define_singleton_method(:keyboard_key_held?) { |key| key == code }
      probe.field.update
      assert(probe.input.empty?, 'async held alone invented a new press')
      probe.frame([[code, true]], held: [code])
      assert(EltenAPI::KeyboardState.pressed?(code), 'real native down was not delivered')
      assert(probe.input == [command], 'earlier asynchronous held state rejected a fresh native press')
    ensure
      EltenWindow.define_singleton_method(:keyboard_key_held?, original)
    end
  end

  check.call("host suppression and release #{code}") do
    probe = AudioBallFastInputProbe.new
    probe.frame([[code, true]], held: [code]); probe.input
    EltenAPI::KeyboardState.suppress_held_until_release
    probe.frame([[code, true]], held: [code])
    assert(probe.input.empty?, 'intentional host suppression was bypassed')
    probe.frame([[code, false], [code, true, probe.state(code)]], held: [code])
    assert(probe.input == [command], 'real release did not re-enable a suppressed key')
  end

  check.call("focus guard and fast release #{code}") do
    probe = AudioBallFastInputProbe.new
    probe.frame([[code, true]], held: [code], update: false)
    probe.field.focus
    probe.field.update
    assert(probe.input.empty?, 'focus replayed the key used outside the field')
    probe.frame([[code, :repeat]], held: [code])
    assert(probe.input.empty?, 'focus guard allowed held navigation repeat')
    probe.frame([[code, false], [code, true, probe.state(code)]], held: [code])
    assert(probe.input == [command], 'fresh release/repress after refocus was lost')
  end
end

check.call('bounded queue retains the latest real direction') do
  probe = AudioBallFastInputProbe.new
  probe.frame(40.times.flat_map { probe.tap(0x28) } + probe.tap(0x26))
  result = probe.input
  assert(result.length == 32 && result.last == 'up', 'overflow discarded the latest direction')
  assert(probe.input.empty?, 'overflow left a second delayed batch of commands')
end

check.call('rapid modified taps do not become plain defence commands') do
  probe = AudioBallFastInputProbe.new
  probe.frame(probe.tap(0x26)); probe.input
  probe.frame([[0x11, true], [0x26, true, probe.state(0x11, 0x26)], [0x26, false], [0x11, false]])
  assert(probe.input.empty?, 'fast modified command escaped the shortcut guard')
  probe.frame(probe.tap(0x26))
  assert(probe.input == ['up'], 'plain new press after a modified tap was lost')
end

raise failures.join("\n") unless failures.empty?
puts "PASS Audio Ball fast native input: #{checks} cases, eight controls, adjacent taps, release/repress, async-held race, suppression and focus"
