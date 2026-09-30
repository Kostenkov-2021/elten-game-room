require_relative "../../support/axel_pong_point_audio"

rules = GameRoomGames::AxelPong.new
mode = rules.option_definitions.find { |option| option.key == 'arcade' }
assert(mode.kind == :choice && mode.choices.map(&:value) == [false, true], 'Pong mode is not a compatible Classic/Arcade choice')

now = 0.0
spoken = []
program = PongAudioProgram.new
audio = GameRoomPong::Audio.new(program, clock: -> { now }, speaker: ->(text) { spoken << text }, speech_active: -> { false })
audio.load
audio.point([21, 11], viewer: 0, winner: 0, finished: true)
now = 3.0
audio.tick
now = 3.5
audio.tick
assert(program.sounds['pong_scores'].playing? && program.sounds['pong_number21'].plays.zero?, 'next number cut off introduction')
program.sounds['pong_scores'].pause
audio.tick
now = 4.5
audio.tick
assert(program.sounds['pong_number21'].playing? && program.sounds['pong_number11'].plays.zero?, 'long number was cut off')
program.sounds['pong_number21'].pause
audio.tick
program.sounds['pong_number11'].pause
now = 7
audio.tick
assert(program.sounds['pong_youwin'].playing?, 'victory not queued')
now = 7.4
audio.tick
assert(program.sounds['pong_youwin'].playing? && program.sounds['pong_scores'].plays == 1, 'victory cut off by repeated score')
program.sounds['pong_youwin'].pause
audio.tick
assert(program.sounds['pong_scores'].plays == 2, 'score did not follow completed victory')
audio.point([23, 21], viewer: 1, score_text: 'Bob: 21; Alice: 23.')
now += 3
audio.tick
assert(spoken == ['Bob: 21; Alice: 23.'], 'above-21 score not read in full')
audio.close
[[10, 9], [11, 10], [20, 19], [21, 20], [22, 21], [57, 56]].each do |scores|
  now, busy = 0.0, false
  messages = []
  program = PongAudioProgram.new
  audio = GameRoomPong::Audio.new(program, clock: -> { now },
    speaker: ->(text) { messages << text; busy = true }, speech_active: -> { busy })
  audio.load
  audio.point(scores, viewer: 1, winner: 0, finished: true,
    score_text: "Bob: #{scores[1]}; Alice: #{scores[0]}.", result_text: 'Alice wins.')
  160.times do
    now += 0.1
    # Simulate playback completion using the sample length, not a short
    # hard-coded gap. Each fake stream otherwise reports playing forever.
    starts = audio.instance_variable_get(:@announcing)
    starts.each { |name, deadline| program.sounds[name].pause if now >= deadline - 0.25 }
    busy = false if (now * 10).round % 10 == 0
    audio.tick
  end
  assert(program.sounds['pong_youwin'].plays.zero? && program.sounds['pong_theywin'].plays == 1, 'observed defeat was missing or repeated')
  assert(messages.count('Alice wins.').zero?, 'neutral observer result duplicated the perspective recording')
  if scores.max > 21
    assert(messages.count("Bob: #{scores[1]}; Alice: #{scores[0]}.") == 2, 'full high score missing around final result')
    assert(program.sounds['pong_scores'].plays.zero?, 'partially recorded high score')
  end
  audio.close
end
puts 'PASS Pong feedback: mode compatibility, complete number/result recordings, full TTS score above 21'
