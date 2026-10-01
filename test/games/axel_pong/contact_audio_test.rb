require_relative '../../support/pong_audio'
require_relative '../../../lib/axel_pong/peer_engine'

class ContactSound < PongSound
  def initialize(name, trace)
    super()
    @name, @trace = name, trace
  end
  def position=(value)
    @trace << [@name, :seek, value, @volume, @pan]
    super
  end
  def play
    @trace << [@name, :play, @position, @volume, @pan]
    super
  end
end

class ContactProgram < PongAudioProgram
  attr_reader :trace
  def initialize; super; @trace = []; end
  def create_sound_from_asset(name, loop:)
    @loops[name] = loop
    @sounds[name] = ContactSound.new(name, @trace)
  end
end

class ContactBot
  def prepare(_engine); end
  def track(_engine); end
  def served(_engine, opening:); end
  def contact(engine); engine.strike(1, bot: true); end
end

def rolling_restarts(program)
  program.trace.count { |name, operation, *_| name == 'pong_ball' && operation == :seek }
end

# The callback runs before even the first advance_motion following bot contact,
# not merely before the final audio update after four catch-up physics frames.
program = ContactProgram.new
audio = GameRoomPong::Audio.new(program)
audio.load
contacts = []
engine = GameRoomPong::PeerEngine.new(side: 0, authority: true, bots: [1], rng: Random.new(12),
  on_feedback: ->(state) {
    contacts << state if %w[serve hit shield_hit].include?(state['fx'].last[1])
    audio.feedback(state, viewer: 0, paused: false)
  })
engine.register_bot(1, ContactBot.new)
engine.strike(0)
engine.ball.merge!('x' => 26.75, 'y' => 20.0, 'dy' => 1, 'speed' => 0.25)
engine.move_to(1, 23.0, silent: true)
trace = program.trace
engine.define_singleton_method(:advance_motion) do
  trace << [:physics, :advance, ball['x'], ball['y']]
  super()
end
trace.clear
4.times { engine.step([{}, {}]) }
contact = contacts.last
assert(contact['b']['x'] == 26.75 && contact['b']['y'] == 20.0, 'callback missed contact coordinates')
impact_at = trace.index { |name, action, *_| name == 'pong_op_hit' && action == :play }
rolling_at = trace.index { |name, action, *_| name == 'pong_ball' && action == :seek }
physics_at = trace.index { |name, action, *_| name == :physics && action == :advance }
assert(impact_at && rolling_at && physics_at && impact_at < rolling_at && rolling_at < physics_at,
  "impact/rolling/physics order changed: #{trace.inspect}")
assert(trace[rolling_at][3].zero?, 'recording restarted with stale audible pan/gain')
assert(program.sounds['pong_ball'].playing?, 'rolling recording did not start at contact')
assert(engine.ball['x'] > contact['b']['x'] && engine.ball['y'] < contact['b']['y'], 'fixture did not advance')
assert(rolling_restarts(program) == 1, 'contact restarted the recording more than once')
3.times { audio.update(engine.snapshot, viewer: 0, paused: false) }
assert(rolling_restarts(program) == 1 && program.sounds['pong_op_hit'].plays == 1,
  'end-of-frame presentation replayed contact audio')
expected_pan, expected_gain = audio.send(:spatial, engine.paddles[0], engine.snapshot['b']['x'], engine.snapshot['b']['y'], 0)
assert(audio.instance_variable_get(:@pans)['pong_ball'] == expected_pan &&
  audio.instance_variable_get(:@levels)['pong_ball'] == expected_gain, 'continued flight stopped updating sound')

# Remote returns have the same boundary, and rejected/duplicate returns never
# call it. No added hook may alter the actual full-precision physics or RNG.
contacts.clear
trace.clear
packet = {'action' => 'hit', 'side' => 0, 'turn' => engine.turn + 1,
  'ball' => engine.ball.merge('x' => 2.25, 'y' => 1.0, 'dy' => 1)}
assert(engine.apply_return(packet), 'legal remote return rejected')
assert(contacts.length == 1 && contacts[0]['b']['x'] == 2.25 && contacts[0]['b']['y'] == 0.0,
  'remote callback did not use the accepted far-baseline position')
assert(!engine.apply_return(packet) && contacts.length == 1, 'duplicate return sounded')
assert(!engine.apply_return(packet.merge('turn' => engine.turn + 2)) && contacts.length == 1, 'future return sounded')
audio.close

variants = [false, true].map do |with_feedback|
  result = []
  e = GameRoomPong::PeerEngine.new(side: 0, authority: true, bots: [1], arcade: true, rng: Random.new(77),
    on_feedback: with_feedback ? ->(state) { result << state } : nil)
  e.register_bot(1, ContactBot.new)
  e.strike(0)
  e.ball.merge!('x' => 26.75, 'y' => 20.0, 'dy' => 1, 'speed' => 0.25)
  e.move_to(1, 23.0, silent: true)
  20.times.map { e.step([{}, {}]); [e.snapshot, e.ball.dup, e.take_transition] }
end
assert(variants[0] == variants[1], 'contact feedback changed physics, effects, transition or RNG')

# Preserve both viewing directions, doubles seat identity, shield returns,
# pause, invisibility, mute and snapshot-only spectator fallback.
%w[serve hit shield_hit].each do |kind|
  [[0, 1], [0, 0, 1, 1]].each do |teams|
    teams.each_index do |viewer|
      p = ContactProgram.new
      a = GameRoomPong::Audio.new(p, rng: Random.new(3))
      a.prepare_players(teams.length)
      a.load
      side = teams.length - 1
      state = {'p' => Array.new(teams.length, 15.0), 'b' => {'x' => 4.5, 'y' => 20.0, 'dy' => -1},
        'teams' => teams, 'invisible' => false, 'fx' => [[1, kind, side, 4.5, 20.0]]}
      a.feedback(state, viewer: viewer, paused: false)
      assert(rolling_restarts(p) == 1 && p.sounds['pong_ball'].playing?, "#{kind}/#{viewer}: contact inaudible")
      expected = a.send(:spatial, 15.0, 4.5, 20.0, teams[viewer])
      assert([a.instance_variable_get(:@pans)['pong_ball'], a.instance_variable_get(:@levels)['pong_ball']] == expected,
        "#{kind}/#{viewer}: wrong contact panorama/depth")
      a.update(state, viewer: viewer, paused: false)
      assert(rolling_restarts(p) == 1, "#{kind}/#{viewer}: duplicate restart")
      a.reset
      p.trace.clear
      a.feedback(state, viewer: viewer, paused: true)
      assert(rolling_restarts(p).zero?, 'paused early feedback played')
      a.update(state, viewer: viewer, paused: true)
      a.update(state, viewer: viewer, paused: false)
      assert(rolling_restarts(p).zero?, 'unpause replayed old contact')
      a.reset
      a.update(state, viewer: viewer, paused: false)
      assert(rolling_restarts(p) == 1, 'snapshot-only listener lost contact or rally reset')
      a.reset
      state['invisible'] = true
      a.feedback(state, viewer: viewer, paused: false)
      assert(!p.sounds['pong_ball'].playing? && p.sounds['pong_ball'].volume.zero?, 'invisible ball became audible')
      a.reset
      state['invisible'] = false
      p.enabled = false
      a.feedback(state, viewer: viewer, paused: false)
      assert(p.sounds.values.none?(&:playing?), 'muted contact played')
      a.close
    end
  end
end

puts 'PASS Pong contact audio: before physics, one restart, unchanged physics/RNG, remote validation, singles/doubles, pause, mute, shields and spectator fallback'
