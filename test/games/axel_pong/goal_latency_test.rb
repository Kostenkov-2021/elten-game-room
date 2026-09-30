require_relative "../../support/axel_pong_point_audio"

[1.0, 6.0].each do |write_delay|
  now = 0.0
  program = PongAudioProgram.new
  audio = GameRoomPong::Audio.new(program, clock: -> { now })
  audio.load
  audio.goal(viewer: 0, winner: 0)
  assert(GameRoomPong::Audio::GOALS.sum { |name| program.sounds[name].plays } == 1, 'agreed goal has no immediate effect')
  now = write_delay
  audio.tick
  assert(program.sounds['pong_scores'].plays.zero?, 'unconfirmed score recording played')
  audio.point([7, 0], viewer: 0, winner: 0, finished: true, goal_at: 0.0)
  assert(GameRoomPong::Audio::GOALS.sum { |name| program.sounds[name].plays } == 1, 'durable replay repeated the goal')
  now = [3.0, write_delay].max
  audio.tick
  assert(program.sounds['pong_scores'].plays == 1, 'durable write added a new three-second pause')
  assert(program.sounds['pong_youwin'].plays.zero?, 'win recording skipped the confirmed score sequence')
  audio.close
end
puts 'PASS goal latency: immediate agreed goal, one- and six-second writes, no premature score/result, no repeated goal pause'
