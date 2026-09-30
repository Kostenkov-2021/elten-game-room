require_relative "../../support/pong_audio"
now = 0.0
program = PongAudioProgram.new
audio = GameRoomPong::Audio.new(program, clock: -> { now }, rng: Random.new(12))
audio.load
state = GameRoomPong::Engine.new.snapshot
number = 0
[0, 1].each do |viewer|
  [0, 4, 8, 12, 16, 20].zip([1.3, 1.15, 1, 0.85, 0.7, 0.7]).each do |depth, pitch|
    state['fx'] = [[number += 1, 'wall', nil, 1, viewer.zero? ? depth : 20 - depth]]
    audio.update(state, viewer: viewer, paused: false)
    sound = program.sounds['pong_wall']
    volume = depth <= 3 ? 1.0 : [0.95 - (depth - 4) * 0.06, 0].max
    assert((sound.frequency / 44100.0 - pitch).abs < 0.000001, 'wall band')
    assert((sound.volume - volume).abs < 0.000001, 'wall distance curve')
  end
  state['p'] = [8, 23]
  state['fx'] = [[number += 1, 'hit', viewer, 29, 10], [number += 1, 'hit', 1 - viewer, 1, 9]]
  audio.update(state, viewer: viewer, paused: false)
  assert(program.sounds['pong_hit'].playing? && program.sounds['pong_op_hit'].playing?, 'two hits cut each other off')
  assert(program.sounds['pong_hit'].pan.zero? && program.sounds['pong_hit'].volume == 1, 'own hit not centred')
  assert((program.sounds['pong_op_hit'].volume - 0.2).abs < 0.000001, 'opponent hit not at far paddle')
  state['fx'] = [[number += 1, 'shield_on', viewer, 2, 12], [number += 1, 'shield_on', 1 - viewer, 29, 5]]
  audio.update(state, viewer: viewer, paused: false)
  # Original nominal gain 2.0 is clipped per stereo channel AFTER the master.
  assert(program.sounds['pong_shield_on'].volume == 1.0 && program.sounds['pong_shield_on'].pan.zero?, 'own shield clipping')
  assert(program.sounds['pong_op_shield_on'].volume == 0.24 && program.sounds['pong_op_shield_on'].pan.zero?, 'far shield')
  40.times do
    state['fx'] = [[number += 1, 'shield_hit', viewer, 6, 0], [number += 1, 'shield_hit', 1 - viewer, 21, 20]]
    audio.update(state, viewer: viewer, paused: false)
    own_hit = GameRoomPong::Audio::SHIELD_HITS.select { |name| name.start_with?('pong_own_') && program.sounds[name].playing? }
    op_hit = GameRoomPong::Audio::SHIELD_HITS.select { |name| name.start_with?('pong_op_') && program.sounds[name].playing? }
    assert(own_hit.all? { |name| program.sounds[name].volume == 1.0 } &&
      op_hit.all? { |name| (program.sounds[name].volume - 0.91).abs < 0.000001 }, 'original shield clipping/default opponent gain')
  end
end
assert(GameRoomPong::Audio::SHIELD_HITS.count { |n| program.sounds[n].plays > 0 } == 20, 'missing randomized shield voices')

assert(audio.echo == 'off' && !audio.toggle_crowd, 'missing crowd recordings advertised as enabled')
assert(audio.cycle_echo == 'noise', 'echo noise toggle')
state['fx'] = []
state['p'][0] = 1.0
audio.update(state, viewer: 0, paused: true)
assert(program.sounds['pong_echo_noise_left'].volume == 0.3 && program.sounds['pong_echo_noise_right'].volume.zero?, 'echo edge distance')
state['p'][0] = 15.0
audio.update(state, viewer: 0, paused: false)
assert(program.sounds['pong_echo_noise_left'].volume == 0.02 && program.sounds['pong_echo_noise_right'].volume == 0.02, 'echo centre distance')
assert(audio.cycle_echo == 'tone', 'echo tone toggle')
audio.update(state, viewer: 0, paused: false)
20.times { audio.update(state, viewer: 0, paused: false) }
assert(program.sounds['pong_echo_tone_left'].plays == 1, 'tone restarted every frame')
now = 0.15
audio.update(state, viewer: 0, paused: false)
assert(program.sounds['pong_echo_tone_left'].plays == 2, 'missing next tone')
program.enabled = false
audio.tick
assert(program.sounds.values.none?(&:playing?), 'echo ignored mute')
assert(audio.cycle_echo == 'off', 'echo off toggle')
audio.close

# Crowd files are absent in production. Verify the prepared hooks only with
# synthetic handles, without claiming that the actual recordings were heard.
program = PongAudioProgram.new
audio = GameRoomPong::Audio.new(program, clock: -> { now }, rng: Random.new(8))
audio.load
crowd_names = %w[pong_crowd_loop pong_crowd_chant pong_crowd_ok1 pong_crowd_ok2
  pong_crowd_won pong_crowd_lost] + (1..5).map { |n| "pong_crowd_cheer#{n}" } +
  (1..2).map { |n| "pong_crowd_epicfail#{n}" }
crowd_names.each do |name|
  sound = program.create_sound_from_asset(name, loop: %w[pong_crowd_loop pong_crowd_chant].include?(name))
  audio.instance_variable_get(:@sounds)[name] = sound
  audio.instance_variable_get(:@frequencies)[name] = sound.frequency
end
assert(audio.toggle_crowd && audio.crowd, 'crowd hooks cannot enable provided handles')
audio.send(:crowd_event, 'chant')
10.times { audio.send(:crowd_event, 'increase') }
audio.send(:update_crowd, false)
assert(program.sounds['pong_crowd_chant'].volume > 0.4 &&
  program.sounds['pong_crowd_loop'].playing?, 'crowd chant/loop progression')
audio.point([1, 0], viewer: 0, winner: 0, finished: true)
assert((1..5).any? { |n| program.sounds["pong_crowd_cheer#{n}"].plays > 0 }, 'missing crowd point reaction')
now += 5.7
audio.tick
assert(program.sounds['pong_crowd_won'].plays == 1, 'missing crowd final reaction')
assert(audio.toggle_crowd && !audio.crowd && crowd_names.none? { |n| program.sounds[n].playing? }, 'crowd mute')
audio.close
puts 'PASS reference audio: five wall bands, stereo/depth, independent hits, 20 shield samples, echo modes/timing/mute, missing crowd'
