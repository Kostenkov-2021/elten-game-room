require_relative "../../support/axel_pong_point_audio"

now = 0.0
program = PongAudioProgram.new
audio = GameRoomPong::Audio.new(program, clock: -> { now }, rng: Random.new(17))
audio.load
audio.point([1, 0], viewer: 1)
goals = GameRoomPong::Audio::GOALS.map { |name| program.sounds[name] }
voices = GameRoomPong::Audio::GOAL_VOICES.map { |name| program.sounds[name] }
assert(goals.sum(&:plays) == 1 && voices.sum(&:plays) == 1, 'missing original goal effect or goal recording')
assert((goals + voices).select(&:playing?).all? { |sound| sound.volume == 0.5 }, 'goal/voice reference volume')
audio.reset
audio.suspend
audio.update(nil, viewer: 1, paused: true)
assert(goals.any?(&:playing?) && voices.any?(&:playing?), 'point recording cut off by rally reset or view refresh')
state = GameRoomPong::Engine.new.snapshot
state['fx'] = [[99, 'goal', 0, 1, 20]]
audio.update(state, viewer: 1, paused: false)
assert(goals.sum(&:plays) == 1 && program.sounds['pong_goal'].plays.zero?, 'replaceable goal effect duplicated accepted point audio')
now = 2.9
audio.tick
assert(program.sounds['pong_scores'].plays.zero?, 'score recording started before its pause')
now = 3.0
audio.tick
assert(program.sounds['pong_scores'].plays == 1, 'missing recorded score introduction')
audio.tick
assert(program.sounds['pong_number0'].plays.zero?, 'score numbers overlapped the introduction')
program.sounds['pong_scores'].pause
now = 3.5
audio.tick
assert(program.sounds['pong_number0'].plays == 1 && program.sounds['pong_number1'].plays.zero?, 'guest score was not first')
program.sounds['pong_number0'].pause
now = 4.0
audio.tick
assert(program.sounds['pong_number1'].plays == 1, 'missing opponent score')
program.sounds['pong_number1'].pause
audio.tick
assert(program.sounds.values.none?(&:playing?), 'completed point presentation left a stream running')

# Mute clears pending recordings; unmuting cannot replay an obsolete score.
audio.point([2, 1], viewer: 0)
program.enabled = false
audio.tick
assert(program.sounds.values.none?(&:playing?), 'mute left a point recording playing')
count = program.sounds.values.sum(&:plays)
program.enabled = true
now += 10
audio.tick
assert(program.sounds.values.sum(&:plays) == count, 'unmuting replayed an old score')
program.gain = 0.2
audio.point([21, 20], viewer: 0)
assert(goals.select(&:playing?).all? { |sound| (sound.volume - 0.1).abs < 0.000001 }, 'point ignored category volume')
program.gain = 0.4
audio.tick
assert(goals.select(&:playing?).all? { |sound| (sound.volume - 0.2).abs < 0.000001 }, 'live volume change did not affect point recording')
now += 3
audio.tick
assert(program.sounds['pong_scores'].playing?, 'score queue stalled when finished notification was missing')
audio.point([22, 21], viewer: 0)
count = program.sounds['pong_scores'].plays
now += 5
audio.tick
assert(program.sounds['pong_scores'].plays == count, 'deuce above recorded range announced an incomplete score')
audio.close
audio.close
assert(program.sounds.values.all?(&:closed) && program.sounds.values.none?(&:playing?), 'point audio leaked at close')

missing = PongAudioProgram.new
def missing.create_sound_from_asset(name, loop:)
  return super if name == 'pong_goal'
  nil
end
fallback = GameRoomPong::Audio.new(missing, clock: -> { now })
fallback.load
fallback.point([1, 0], viewer: 0)
assert(missing.sounds['pong_goal'].plays == 1, 'missing optional recordings removed fallback goal sound')
now += 5
fallback.tick
fallback.close

# Exercise the GameScreen event hook, view detachment and final-match tick.
# Both the score and its event order come from real replay, not a hand-built
# score Hash. Final recordings must advance even without a new Pong timer.
rules = GameRoomGames::AxelPong.new
repository = Object.new
def repository.players_for(session); session['__players']; end
def repository.actor_of(event, _session); event['actor']; end
def repository.event_id(event); event['__id']; end
session = {'__players' => %w[Alice Bob], 'player_one' => 'Alice',
  'options' => JSON.generate(rules.default_options.merge('target' => 7))}
events = 7.times.map { |i| {'__id' => i + 1, 'actor' => 'Alice', 'action' => 'pong_point', 'value' => "#{i}:0"} }
before = rules.replay(session, events[0...-1], repository)
after = rules.replay(session, events, repository)
module Session
  def self.name; 'Bob'; end
end
program = PongAudioProgram.new
audio = GameRoomPong::Audio.new(program, clock: -> { now })
audio.load
client = GameRoomPong::Client.new(program, rules, clock: -> { now }, audio: audio,
  channel_factory: ->(**args) { PongTestChannel.new({}, **args) })
client.bind_screen(session_id: 88, table_id: 7, owner: 'Alice', viewer: 'Bob', members: -> { %w[Alice Bob] })
client.before_wait(after, 'Bob')
screen = GameScreen.allocate
{game_client: client, game: rules, repository: repository, program: program, surface_state: {}}.each do |key, value|
  screen.instance_variable_set("@#{key}", value)
end
screen.define_singleton_method(:log_signal_timing) { |*_args, **_options| }
screen.send(:present_game_event, events.last, before, after, after, nil)
client.event(events.last, before, after, 'Bob', repository)
assert(GameRoomPong::Audio::GOALS.sum { |name| program.sounds[name].plays } == 1, 'duplicate accepted point replayed sound')
form = Form.new([])
client.attach_view(form, PongTestSurface.new)
client.detach_view
assert(GameRoomPong::Audio::GOAL_VOICES.any? { |name| program.sounds[name].playing? }, 'finished screen detached goal announcement')
now += 3
client.tick
assert(program.sounds['pong_scores'].plays == 1, 'finished match did not advance score audio')
program.sounds['pong_scores'].pause
now += 0.5
client.tick
assert(program.sounds['pong_number0'].plays == 1, 'final score has wrong viewer order')
program.sounds['pong_number0'].pause
now += 0.5
client.tick
assert(program.sounds['pong_number7'].plays == 1, 'final winning score missing')
now += 1.7
client.tick
assert(program.sounds['pong_number7'].playing? && program.sounds['pong_theywin'].plays.zero?, 'final number cut off by result')
program.sounds['pong_number7'].pause
client.tick
assert(program.sounds['pong_theywin'].plays == 1, 'missing original final losing announcement')
assert(program.sounds['pong_youwin'].plays.zero?, 'wrong final perspective')
client.close

puts 'PASS Pong point audio: reliable event/dedup, original FX and voices, nonblocking ordered score, reset/detach/final result, mute/gain, deuce fallback and cleanup (no device playback)'
