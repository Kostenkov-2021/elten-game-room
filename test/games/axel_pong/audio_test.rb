require_relative "../../support/pong_audio"

program = PongAudioProgram.new
audio = GameRoomPong::Audio.new(program)
audio.load
assert(program.loops.select { |_, looping| looping }.keys.sort ==
  %w[pong_ball pong_echo_noise_left pong_echo_noise_right], 'wrong looping sounds')
engine = GameRoomPong::Engine.new
engine.strike(0)
state = engine.snapshot
state['b'].merge!('x' => 20.0, 'y' => 5.0)
audio.update(state, viewer: 0, paused: false)
rolling = program.sounds['pong_ball']
assert(rolling.pan > 0 && rolling.volume == 0.8, 'own-end pan/distance')
audio.update(state, viewer: 1, paused: false)
assert(rolling.pan > 0 && rolling.volume == 0.4, 'opposite-end shared X orientation')
hit = program.sounds['pong_hit']
assert(hit.plays == 1, 'same full snapshot replayed effect')
state['fx'] = [[2, 'hit', 0, 15, 0], [3, 'shield_on', 0, 15, 0], [4, 'invisible', 0, 15, 0]]
audio.update(state, viewer: 0, paused: false)
assert(%w[pong_hit pong_shield_on pong_invisible].all? { |n| program.sounds[n].playing? }, 'independent effects did not overlap')
state['invisible'] = true
audio.update(state, viewer: 0, paused: false)
assert(rolling.volume.zero?, 'invisible ball remained audible')
state['invisible'] = false
program.gain = 0.2
audio.update(state, viewer: 0, paused: false)
assert((rolling.volume - 0.16).abs < 0.000001, 'shared gain ignored')
program.enabled = false
state['fx'] = [[5, 'goal', 0, 1, 20]]
audio.update(state, viewer: 0, paused: false)
assert(rolling.volume.zero? && program.sounds['pong_goal'].volume.zero?, 'disabled game sounds still audible')
program.enabled = true
audio.update(state, viewer: 0, paused: true)
assert(rolling.volume.zero?, 'paused ball audible')
audio.silence
assert(program.sounds.values.none?(&:playing?), 'detached form did not silence streams')
audio.close
audio.close
assert(program.sounds.values.all?(&:closed) && program.released.length == GameRoomPong::Audio::ASSETS.length && program.managed.length == GameRoomPong::Audio::ASSETS.length, 'sound resources leaked/double release')
missing = PongAudioProgram.new
def missing.create_sound_from_asset(_name, loop:); nil; end
audio = GameRoomPong::Audio.new(missing)
audio.load; audio.update(state, viewer: 0, paused: false); audio.close
puts 'PASS Pong audio: spatial rotation/distance, effect dedup/overlap, invisibility, shared mute/gain, missing assets, cleanup (no device playback)'
