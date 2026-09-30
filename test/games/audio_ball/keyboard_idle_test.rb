require_relative "../../support/audio_ball_native_keys"

keyboard = EltenAPI::KeyboardState
observer = GameRoomAudioBall::Keyboard
observer.install
original_update = keyboard.method(:update)
original_update = original_update.super_method until original_update.owner == keyboard.singleton_class
native_held = keyboard.method(:held?)
held_reads = 0
keyboard.define_singleton_method(:held?) do |*args|
  held_reads += 1
  native_held.call(*args)
end
poll = ->(update) do
  result = update.call(raw_state: "\0" * 256, events: [], now: 1.0,
    synthesize_repeats: false, pressed_implies_held: false)
  $input_frame_serial = $input_frame_serial.to_i + 1
  $keyboard_state_frame_serial = $input_frame_serial
  $keyboard_state_frame_thread = Thread.current
  assert(result.equal?(keyboard.current), 'observer replaced the native result')
  result
end

keyboard.reset
1000.times { poll.call(original_update) }
native_reads = held_reads
held_reads = 0
1000.times do
  result = poll.call(keyboard.method(:update))
  assert(!result.instance_variable_defined?(observer::FRAME), 'idle observer attached metadata')
end
assert(held_reads == native_reads, 'idle observer scanned held keys')

first = GameSurfaces::AudioBallField.new('First game')
first.extend(EltenAPI::UI)
first.focus
held_reads = 0
1000.times { poll.call(keyboard.method(:update)) }
assert(held_reads == native_reads + 19_000, 'focused observer did not snapshot exactly its 19 keys')
assert(keyboard.current.instance_variable_get(observer::FRAME).is_a?(observer::Frame), 'active observer did not capture')
first.blur
assert(!observer.active?, 'blur kept observer active')
assert(!keyboard.current.instance_variable_defined?(observer::FRAME), 'blur kept retired metadata')

second = GameSurfaces::AudioBallField.new('Replacement game')
second.extend(EltenAPI::UI)
second.focus
first.deactivate_input
assert(observer.active?, 'late old-field detach disabled the replacement')
held_reads = 0
poll.call(keyboard.method(:update))
assert(held_reads == 19, 'replacement stopped observing input')
second.deactivate_input
held_reads = 0
1000.times { poll.call(keyboard.method(:update)) }
assert(held_reads == native_reads, 'detached observer still scanned keys')

def ephemeral_field
  field = GameSurfaces::AudioBallField.new('Disposed field')
  field.extend(EltenAPI::UI)
  field.focus
  WeakRef.new(field)
end
# Unwind the creator's VM stack before GC: conservative stack slots may keep
# a dead local alive even when the observer itself only holds a WeakRef.
reference = Thread.new do
  $keyboard_state_frame_thread = Thread.current
  ephemeral_field
end.value
$keyboard_state_frame_thread = Thread.current
10.times { GC.start(full_mark: true, immediate_sweep: true) }
assert(!reference.weakref_alive? && !observer.active?, 'observer retained a discarded game field')

h = AudioBallNativeKeys.new
begin
  assert(observer.active?, 'client attach did not activate its focused field')
  h.clients.fetch('Bob').detach_view
  assert(!observer.active?, 'client detach kept the observer active')
  h.clients.fetch('Bob').attach_view(h.forms.fetch('Bob'), h.surfaces.fetch('Bob'))
  assert(observer.active?, 'client reattach did not restore focused input')
ensure
  h.close
end
assert(!observer.active?, 'closing clients kept observer active')
puts 'PASS native Audio Ball idle observer: zero extra scans/metadata, focus/blur, replacement, weak field lease, client detach/reattach/close'
