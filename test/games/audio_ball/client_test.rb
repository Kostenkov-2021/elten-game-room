require_relative "../../support/audio_ball_client"

$audio_ball_client_tests = 0

def client_test(name)
  yield
  $audio_ball_client_tests += 1
  puts "PASS Audio Ball client: #{name}"
end

client_test('independent client binds the shared reliable peer lane') do
  assert(defined?(GameRoomAudioBall::Client), 'Audio Ball realtime client is missing')
  assert(GameRoomAudioBall::Client.superclass == Object, 'Audio Ball inherited Pong gameplay')
  network = {}
  audio = AudioBallTestAudio.new
  client = GameRoomAudioBall::Client.new(Program.new, GameRoomGames::AudioBall.new, audio: audio,
    channel_factory: ->(**args) { AudioBallTestChannel.new(network, **args) })
  client.bind_screen(session_id: 300, table_id: 20, owner: 'Alice', viewer: 'Alice', members: -> { %w[Alice Bob] })
  assert(client.start, 'client did not start')
  assert(network['alice'].event_protocol == 'audio-ball-peer-2' && network['alice'].routing == :peers, 'gameplay is not on the agreed-goal peer dialect')
  assert(audio.calls.include?([:load]), 'audio was not loaded')
  client.close
  client.close
  assert(audio.calls.count([:close]) == 1 && !network['alice'].connected?, 'close did not release resources exactly once')
end

client_test('two humans use fresh attacks and lane defense through direct peer events') do
  h = AudioBallHarness.new(options: {'difficulty' => 1})
  h.advance(12)
  assert(h.clients.values.none?(&:paused), 'readiness deadlocked')
  assert(h.audios.values.all? { |audio| audio.calls.count([:set, 1]) == 1 }, 'first set was not announced once')
  h.press('Alice', 'up')
  assert(h.clients['Alice'].engine.phase == :waiting, 'shot skipped preparation')
  h.press('Alice', 'prepare', 'up')
  assert(h.clients.values.all? { |client| client.engine.phase == :flying && client.engine.turn == 2 }, 'owned hit was not applied by all peers')
  h.press('Bob', 'left')
  h.advance_for(h.clients['Bob'].engine.duration * 0.94)
  assert(h.clients['Bob'].engine.phase == :flying, 'wrong lane caught the ball')
  h.press('Bob', 'up')
  h.advance(2, names: %w[Bob Watcher])
  assert(h.clients['Watcher'].engine.phase == :waiting && h.clients['Watcher'].engine.holder == 1, 'defense waited for owner forwarding')
  h.advance(2)
  assert(h.clients.values.all? { |client| client.engine.turn == 3 && client.engine.holder == 1 }, 'clients disagree after a legal defense')
  assert(h.audios['Bob'].calls.count { |call| call[0] == :prepare } == 1, 'remote prepare audio was duplicated')
  h.close
end

client_test('only agreed goals enter durable replay and slow commits cannot start a rally') do
  h = AudioBallHarness.new
  h.advance(12)
  h.network['bob'].drop = true
  h.press('Alice', 'prepare', 'left')
  h.advance(100)
  assert(h.clients['Bob'].engine.goal == 0 && h.clients['Alice'].engine.goal == 0, 'rightful receiver did not report its miss')
  assert(h.clients['Alice'].context_data['audio_ball_point'] == nil, 'owner scored before the other human acknowledged the goal')
  h.network['bob'].drop = false
  h.advance(5)
  point = h.clients['Alice'].context_data['audio_ball_point']
  assert(point == '0:0', 'agreed goal did not reach context_data')
  h.advance(200)
  h.press('Alice', 'prepare', 'up')
  assert(h.replay.state[:scores] == [0, 0] && h.clients['Alice'].engine.phase == :over, 'client changed durable scores or served before commit')
  h.commit
  assert(h.replay.state[:scores] == [1, 0] && h.clients['Alice'].context_data['audio_ball_point'] == nil, 'durable point was not consumed once')
  assert(h.audios.values.all? { |audio| audio.calls.count { |call| call[0] == :point } == 1 }, 'durable result announcement was missing or duplicated')
  h.press('Alice', 'prepare', 'up')
  h.advance_for(5.8)
  assert(h.clients.values.all? { |client| client.engine.phase == :waiting }, 'a paused key survived the point break')
  h.press('Alice', 'prepare', 'down')
  assert(h.clients['Alice'].engine.phase == :flying, 'next rally did not resume after the explicit point break')
  h.close
end

client_test('hurry survives simultaneous preparation and only the holder times out') do
  h = AudioBallHarness.new(options: {'difficulty' => 1})
  h.advance(12)
  h.press('Alice', 'prepare', 'up')
  h.advance_for(h.clients['Bob'].engine.duration * 0.94)
  h.press('Bob', 'up')
  h.advance(4)
  assert(h.clients.values.all? { |client| client.engine.holder == 1 }, 'setup did not catch the ball')
  h.network['alice'].hold_events = true
  h.surfaces['Alice'].on_audio_ball_command.call('hurry')
  assert(h.clients['Alice'].engine.warning != nil && h.clients['Bob'].engine.warning == nil, 'receiver warning started before receipt')
  h.press('Bob', 'prepare')
  h.network['alice'].release_events
  h.advance(3)
  assert(h.clients.values.all? { |client| client.engine.warning != nil }, 'prepare race invalidated the same-possession warning')
  before = h.clients['Bob'].engine.warning
  h.surfaces['Alice'].on_audio_ball_command.call('hurry')
  h.advance(3)
  assert(h.clients['Bob'].engine.warning < before, 'repeat hurry extended the countdown')
  assert(h.audios['Bob'].calls.count { |call| call[0] == :hurry } == 1, 'same warning was announced twice')
  h.advance(650)
  assert(h.clients['Alice'].context_data['audio_ball_point'] == '0:0:timeout', 'holding a prepared ball escaped the timeout')
  misses = h.network['bob'].event_sent.map { |data| JSON.parse(data)['d'] }.select { |data| data['action'] == 'miss' }
  assert(misses.length == 1 && misses.first['reason'] == 'timeout', 'holder did not emit exactly one authoritative timeout')
  assert(h.network['alice'].event_sent.none? { |data| JSON.parse(data)['d']['action'] == 'miss' }, 'foreign clock produced the timeout')
  h.close
end

client_test('owner and bot play locally without waiting for an endpoint') do
  bot = GameRoomParticipants.bot_id(20, 1)
  h = AudioBallHarness.new(players: ['Alice', bot], viewers: ['Alice'], connected: false)
  h.advance(4)
  assert(!h.clients['Alice'].paused, 'local owner waited for Communications')
  h.press('Alice', 'prepare', 'up')
  h.advance(30)
  turn = h.clients['Alice'].engine.turn
  position = h.clients['Alice'].engine.position
  h.network['alice'].connected = true
  h.network['alice'].epoch = 'generation1'
  h.advance
  assert(h.clients['Alice'].engine.turn >= turn && h.clients['Alice'].engine.position != position, 'first endpoint attachment restarted local play')
  h.advance(500)
  assert(h.clients['Alice'].context_data['audio_ball_point'] != nil, 'local bot match never resolved a rally')
  h.commit
  assert(h.replay.state[:rally] == 1, 'bot match bypassed the durable point path')
  h.close
end

client_test('missing humans pause every copy and reconnection drops only unconfirmed play') do
  h = AudioBallHarness.new
  h.advance(12)
  h.press('Alice', 'prepare', 'up')
  h.network['alice'].missing = ['bob']
  h.advance(5)
  assert(h.clients.values.all?(&:paused), 'owner readiness let other copies continue without a human')
  positions = h.clients.transform_values { |client| client.engine.position }
  h.advance(10, seconds: 0.2)
  assert(h.clients.all? { |name, client| client.engine.position == positions[name] }, 'unhealthy network advanced ball clocks')
  h.network['alice'].missing = []
  h.network.each_value { |channel| channel.epoch = 'generation2' }
  h.press('Alice', 'prepare', 'up')
  h.advance(12)
  assert(h.clients.values.all? { |client| client.engine.turn == 0 && !client.paused }, 'reconnect replayed unconfirmed input or deadlocked readiness')
  h.press('Alice', 'prepare', 'up')
  h.advance(100)
  pending = h.clients['Alice'].context_data['audio_ball_point']
  assert(pending == '0:0', 'setup did not agree a point')
  h.network.each_value { |channel| channel.epoch = 'generation3' }
  h.advance(12)
  assert(h.clients['Alice'].context_data['audio_ball_point'] == pending, 'reconnect discarded an already agreed point')
  assert(h.clients.values.all?(&:paused), 'reconnection made a pending agreed rally playable before durable commit')
  h.commit
  assert(h.replay.state[:rally] == 1, 'agreed reconnect point was lost')
  h.close
end

client_test('authenticated cross-sender actions are ordered and bounded') do
  h = AudioBallHarness.new(players: %w[Bob Carol], owner: 'Alice')
  h.advance(12)
  prepare = {'action' => 'prepare', 'side' => 0, 'turn' => 1}
  ['Watcher', 'Alice', 'Carol'].each { |sender| h.inject('Alice', sender, prepare) }
  h.inject('Alice', 'Bob', prepare, match: 'another-match')
  h.inject('Alice', 'Bob', prepare, epoch: 'old-generation')
  h.inject('Alice', 'Bob', prepare.merge('r' => -1))
  h.advance
  assert(h.clients['Alice'].engine.turn == 0, 'foreign player, match, epoch or rally changed the game')
  h.inject('Alice', 'Carol', {'action' => 'defend', 'side' => 1, 'turn' => 3, 'shot' => 'up'})
  h.inject('Alice', 'Bob', {'action' => 'hit', 'side' => 0, 'turn' => 2, 'shot' => 'up'})
  h.inject('Alice', 'Bob', prepare)
  h.advance
  assert(h.clients['Alice'].engine.turn == 3 && h.clients['Alice'].engine.holder == 1, 'cross-sender causal ordering lost an action')
  h.inject('Alice', 'Bob', prepare)
  h.advance
  assert(h.clients['Alice'].engine.turn == 3, 'duplicate transition changed state')
  h.inject('Alice', 'Carol', {'action' => 'prepare', 'side' => 1, 'turn' => 100_000})
  h.advance
  assert(h.network['alice'].resets > 0 && h.clients['Alice'].paused, 'unbounded action gap did not enter recovery')
  assert(h.clients['Alice'].send(:rally_state).deferred.length <= GameRoomRealtime::EventChannel::LIMIT, 'deferred action storage grew without a bound')
  h.close
end

client_test('stale one-way heartbeats recover automatically without a ready feedback loop') do
  h = AudioBallHarness.new
  h.advance(12)
  h.network['bob'].drop = true
  h.advance(320)
  assert(h.clients.values.all?(&:paused), 'one-way stale traffic left a client playable')
  assert(h.network['alice'].reasons.include?('AudioBallStatusTimeout'), 'stale human did not trigger automatic recovery')
  h.network['bob'].drop = false
  h.network.each_value { |channel| channel.epoch = 'recovered' }
  h.advance(15)
  assert(h.clients.values.none?(&:paused), 'independent readiness did not recover after fresh heartbeats')
  h.close
end

client_test('owner spectator delegates only bots and late spectators restore the current flight') do
  bot = GameRoomParticipants.bot_id(20, 1)
  h = AudioBallHarness.new(players: [bot, 'Bob'], viewers: %w[Alice Bob Watcher])
  h.advance(80)
  assert(h.clients['Bob'].engine.phase == :flying, 'owner spectator did not serve with its bot')
  h.add_client('Late')
  h.advance(4)
  assert(h.clients['Late'].engine.turn == h.clients['Alice'].engine.turn && h.clients['Late'].engine.phase == :flying, 'late spectator kept a turn-zero engine')
  h.press('Watcher', 'prepare', 'up')
  assert(!h.surfaces['Watcher'].on_audio_ball_command.call('hurry'), 'spectator issued a warning')
  h.advance(100)
  assert(h.clients['Alice'].context_data['audio_ball_point'] == '0:0', 'owner spectator did not obtain human agreement')
  assert(h.clients['Watcher'].context_data['audio_ball_point'] == nil, 'spectator attempted to score')
  owned = h.network['alice'].event_sent.map { |data| JSON.parse(data)['d'] }
  assert(owned.all? { |data| data['side'] == 0 }, 'owner simulated the human side')
  h.commit
  point = h.audios['Watcher'].calls.find { |call| call[0] == :point }
  assert(point[2][:viewer] == nil, 'spectator result says that the spectator won or lost')
  h.close
end

client_test('background network UI progresses time but never consumes playable input') do
  h = AudioBallHarness.new
  h.advance(12)
  h.press('Alice', 'prepare', 'up')
  h.surfaces['Bob'].push('up')
  client = h.clients['Bob']
  ui = client.network_task_ui(ui: Object.new, title: 'Saving', show_after: 100.0, cancellation_token: nil)
  h.now += 0.2
  before = client.engine.position
  ui.update
  assert(client.engine.position != before, 'background network UI stopped realtime progression')
  assert(client.engine.turn == 2, 'progress window played a queued key')
  client.detach_view
  assert(h.surfaces['Bob'].on_audio_ball_command == nil, 'detached view retained its command handler')
  client.attach_view(h.forms['Bob'], h.surfaces['Bob'])
  h.advance(100)
  assert(client.engine.goal == 0, 'progress-window input became a delayed defense')
  ui.close
  h.close
end

client_test('complete two-set match pauses five seconds after result then announces the next set') do
  h = AudioBallHarness.new(options: {'sets_to_win' => 2})
  h.advance(12)
  h.points_to_win.times do |point|
    h.win_point('Alice')
    h.advance_for(5.8) unless point == h.points_to_win - 1
  end
  assert(h.replay.state[:sets] == [1, 0] && h.replay.state[:set_number] == 2, 'first set did not finish through real play and replay')
  result_at = h.now
  h.press('Bob', 'prepare', 'up')
  h.advance(24, seconds: 0.2)
  assert(h.now - result_at < 5.0 && h.clients.values.all?(&:paused), 'set break was shortened')
  assert(h.audios.values.none? { |audio| audio.calls.include?([:set, 2]) }, 'second set was announced before the result pause')
  h.advance(20)
  assert(h.audios.values.all? { |audio| audio.calls.count([:set, 2]) == 1 }, 'second set was not announced once after five seconds')
  assert(h.clients.values.all? { |client| client.engine.turn == 0 }, 'presses made in the set pause leaked into play')
  h.points_to_win.times do |point|
    h.win_point('Alice')
    h.advance_for(5.8) unless point == h.points_to_win - 1
  end
  assert(h.replay.finished? && h.replay.winner == 'Alice' && h.replay.state[:sets] == [2, 0], 'two-set match did not finish')
  assert(h.network.values.none?(&:connected?), 'finished match left realtime channels connected')
  assert(h.audios.values.all? { |audio| audio.calls.count { |call| call[0] == :point } == h.points_to_win * 2 }, 'result audio was duplicated or omitted')
  assert(h.clients.values.all? { |client| client.presents_game_result?(h.replay) }, 'result hook allows duplicate shared announcements')
  h.close
end

client_test('fresh status cannot conceal a lost reliable action indefinitely') do
  h = AudioBallHarness.new
  h.advance(12)
  h.network['alice'].hold_events = true
  h.press('Alice', 'prepare', 'up')
  h.advance(320)
  assert(h.clients['Alice'].context_data['audio_ball_point'] == nil, 'owner awarded a point without remote gameplay agreement')
  assert(h.network['alice'].reasons.include?('AudioBallActionDisagreement'), 'fresh heartbeats concealed a missing gameplay event')
  assert(h.clients.values.all?(&:paused), 'unresolved gameplay disagreement was not paused')
  h.close
end

client_test('first resumed frame drains keys and detached views silence audio') do
  bot = GameRoomParticipants.bot_id(20, 1)
  h = AudioBallHarness.new(players: ['Alice', bot], viewers: ['Alice'], connected: false)
  h.advance(4)
  h.press('Alice', 'prepare', 'up')
  h.advance(500)
  h.commit
  h.surfaces['Alice'].push('prepare', 'up')
  h.now += 5.71
  h.clients['Alice'].frame
  assert(h.clients['Alice'].engine.turn == 0, 'key queued during a pause played on the first resumed frame')
  h.press('Alice', 'prepare', 'up')
  assert(h.clients['Alice'].engine.phase == :flying, 'fresh post-resume press was discarded')
  h.clients['Alice'].detach_view
  assert(h.audios['Alice'].calls.last[0] == :update && h.audios['Alice'].calls.last[3] == true, 'detaching left the flight sound playing')
  h.close
end

client_test('late spectator waits for a snapshot before buffering high-turn peer events') do
  h = AudioBallHarness.new
  h.advance(12)
  h.add_client('Late')
  h.inject('Late', 'Alice', {'action' => 'prepare', 'side' => 0, 'turn' => 500})
  h.advance(names: ['Late'])
  assert(h.network['late'].resets == 0, 'late spectator treated missing historical transitions as a transport failure')
  h.advance(5)
  assert(!h.clients['Late'].paused && h.clients['Late'].engine.turn == h.clients['Alice'].engine.turn, 'late spectator failed to synchronize from owner state')
  h.close
end

client_test('owner snapshots cannot replace human authority or the durable server') do
  h = AudioBallHarness.new
  h.advance(12)
  owner = h.network['alice']
  packet = JSON.parse(owner.sent.last)
  packet['n'] += 1
  foreign = GameRoomAudioBall::Engine.new(level: 1, server: 1)
  foreign.press(1, 'prepare')
  packet['d'].merge!('state' => foreign.snapshot, 'turn' => foreign.turn)
  %w[bob watcher].each { |name| h.network[name].inbox['alice'] = packet }
  h.advance(names: %w[Bob Watcher])
  assert(h.clients['Bob'].engine.turn == 0, 'owner snapshot replaced a human engine')
  assert(h.clients['Watcher'].engine.server == 0 && h.clients['Watcher'].engine.level == 3, 'snapshot overrode durable server or table difficulty')
  h.close
end

puts "All #{$audio_ball_client_tests} Audio Ball client tests passed"
