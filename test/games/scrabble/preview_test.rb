require_relative '../../support/pong_client'
require_relative '../../support/native_room_harness'
require_relative '../../support/native_public_messages'
require_relative '../../support/word_picker'
require_relative '../../../games/scrabble'
require_relative '../../../lib/scrabble_preview'

class PreviewImmediateWork
  def start; @result = [yield, nil]; true; rescue StandardError => e; @result = [nil, e]; true; end
  def take; value, @result = @result, nil; value; end
  def busy?; !!@result; end
  def close; @result = nil; end
end

$activecontrols = $lastactivecontrols = nil
game = GameRoomGames::Scrabble.new
h = NativeRoomHarness.new(game: game, users: %w[Alice Bob Watcher])
h.start
state = game.initial_state(%w[Alice Bob], game.normalize_options('content_language_id' => 'en'))
tiles = game.tiles(state)
ids = %w[c a t].map { |letter| tiles.index { |tile| tile[:letter] == letter } }
blank = tiles.index { |tile| tile[:letter].empty? }
state.merge!(phase: :playing, current_player: 'Alice', revision: 1, turn: 1,
  racks: {'Alice' => [*ids, blank], 'Bob' => []})
replay = GameRoomGames::Replay.new(players: state[:players], current_player: 'Alice', state: state, history: [])
now = 0.0
clients, surfaces = {}, {}
add = lambda do |name, work = PreviewImmediateWork.new|
  program = Program.new
  client = GameRoomScrabblePreview.new(program, game, transport: h.transports[name], clock: -> { now }, work: work)
  client.bind_screen(session_id: h.session['__id'], table_id: h.table['__id'], owner: 'Alice', viewer: name, members: -> { h.users })
  client.start
  client.update_table_control('__control_epoch' => 1)
  client.before_wait(replay, name)
  surface = GameSurfaces.build(game.surface_spec(replay, name))
  client.attach_view(Form.new(surface.fields), surface)
  clients[name], surfaces[name] = client, surface
end
h.users.each { |name| add.call(name) }
pump = ->(n = 4) { n.times { now += 0.13; clients.each_value(&:tick) } }
remote = ->(name) { clients[name].instance_variable_get(:@remote) }
initial_model, initial_events = Marshal.dump(state), Marshal.dump(h.events('Alice'))
begin
  pump.call
  alice = surfaces['Alice']
  alice.handle_command('word_place', 'slot' => 0)
  pump.call
  assert(remote.call('Bob').first[:letter] == 'c' && remote.call('Watcher') == remote.call('Bob'), 'Other player/observer missed placed tile')
  field = surfaces['Watcher'].fields.first
  field.set_logical_position(2, 4)
  alice.fields.first.set_logical_position(8, 7)
  WordPickerTest.answers << game.language(state).alphabet.index('a')
  alice.handle_command('word_place', 'slot' => 3)
  pump.call
  assert(remote.call('Watcher').last.values_at(:letter, :blank, :points) == ['a', true, 0], 'Blank leaked/lost its chosen face')
  assert(field.logical_position == [2, 4], 'Remote preview moved cursor')
  packets = h.users.flat_map { |user| h.view(user).sent_messages.to_a }
  assert(packets.all? { |p| p['payload']['tiles'].to_a.all? { |t| t.size == 3 && t[0].is_a?(Integer) && t[1].is_a?(String) && [true, false].include?(t[2]) } }, 'Payload includes more than public faces')
  assert(!JSON.generate(packets).match?(/rack|placements|tile_id/), 'Rack identity leaked in preview')
  assert(Marshal.dump(state) == initial_model && Marshal.dump(h.events('Alice')) == initial_events, 'Preview changed board/score/stack')
  count = packets.size
  30.times { |i| alice.fields.first.set_logical_position(i % 15, i % 15); pump.call(1) }
  assert(h.users.sum { |u| h.view(u).sent_messages.to_a.size } == count, 'Cursor movement sends network messages')
  old = h.view('Alice').sent_messages.last
  alice.handle_command('word_cancel')
  pump.call
  assert(remote.call('Watcher').empty?, 'Cancel left remote tiles')
  sender = h.core.participants.fetch('alice')
  3.times { h.view('Watcher').deliver_message(sender, old, NativeLiveSessionsBroker::MessageInfo.new) }
  pump.call
  assert(remote.call('Watcher').empty?, 'Old/repeated sketch returned after cancellation')
  alice.fields.first.set_logical_position(7, 7)
  alice.handle_command('word_place', 'slot' => 0)
  pump.call
  clients['Watcher'].close
  add.call('Watcher')
  pump.call
  assert(remote.call('Watcher').size == 1, 'Rejoining observer failed to request current sketch')
  bad = Marshal.load(Marshal.dump(h.view('Alice').sent_messages.last))
  bad['payload']['sequence'] += 10
  bad['payload']['tiles'] = [[113, 'z', false]]
  h.view('Watcher').deliver_message(h.core.participants.fetch('bob'), bad, NativeLiveSessionsBroker::MessageInfo.new)
  pump.call
  assert(remote.call('Watcher').first[:letter] == 'c', 'Non-current player overwrote sketch')
  bad['payload']['tiles'] = [[999, 'z', false]]
  h.view('Watcher').deliver_message(sender, bad, NativeLiveSessionsBroker::MessageInfo.new)
  pump.call
  assert(remote.call('Watcher').first[:letter] == 'c', 'Malformed field overwrote sketch')
  previous_stream = h.view('Alice').sent_messages.last
  clients['Alice'].close
  add.call('Alice')
  surfaces['Alice'].handle_command('word_place', 'slot' => 1)
  pump.call(8)
  assert(remote.call('Watcher').first[:letter] == 'a', 'Restarted author did not complete fresh snapshot handshake')
  h.view('Watcher').deliver_message(sender, previous_stream, NativeLiveSessionsBroker::MessageInfo.new)
  pump.call(8)
  assert(remote.call('Watcher').first[:letter] == 'a', 'Retired author stream replaced current sketch')
  private_packet = h.view('Alice').sent_messages.last
  private_packet = Marshal.load(Marshal.dump(private_packet))
  private_packet['payload']['sequence'] += 100
  private_packet['payload']['tiles'] = [[113, 'z', false]]
  h.view('Watcher').deliver_message(sender, private_packet, NativeLiveSessionsBroker::MessageInfo.new('Watcher'))
  pump.call
  assert(remote.call('Watcher').first[:letter] == 'a', 'Private message entered the public preview lane')
  # A timeout, invalid submission, turn change or replacement changes the
  # replay revision/control scope; no preview may cross that boundary.
  state[:revision] += 1
  state[:current_player] = 'Bob'
  clients.each { |name, client| client.before_wait(replay, name); surfaces[name].update_spec(game.surface_spec(replay, name)) }
  h.view('Watcher').deliver_message(sender, old, NativeLiveSessionsBroker::MessageInfo.new)
  pump.call
  assert(remote.call('Watcher').empty?, 'Previous turn returned')
  clients.each_value { |c| c.update_table_control('__control_epoch' => 2); c.before_wait(replay, 'Alice') }
  pump.call
  assert(remote.call('Watcher').empty?, 'Previous controller returned')
  puts 'PASS Scrabble preview: native message lane, player/observer, blank, cancellation, ordering, rejoin, scope, privacy, cursor, no stack writes'
ensure
  clients.each_value(&:close)
end

# Real worker stalled in native send: edit/cancel can continue and only the
# newest pending sketch survives. Failed delivery is retried, not a lost move.
clients.clear
state[:revision] += 1
state[:current_player] = 'Alice'
gate = Queue.new
h.view('Alice').message_gate = gate
add.call('Alice', GameRoomBackground::Work.new)
add.call('Watcher')
count = h.view('Alice').sent_messages.size
now += 0.13
clients['Alice'].tick
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
100.times do
  surfaces['Alice'].handle_command('word_cancel')
  surfaces['Alice'].handle_command('word_place', 'slot' => 0)
  now += 0.13
  clients.each_value(&:tick)
end
assert(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started < 0.3, 'Slow send blocked UI editing')
assert(h.view('Alice').sent_messages.size == count, 'Stalled operation spawned additional sends')
h.view('Alice').message_gate = nil
gate << true
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
until remote.call('Watcher').size == 1
  raise 'Latest coalesced sketch not delivered' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  pump.call(1)
  sleep 0.001
end
assert(h.view('Alice').sent_messages.size - count <= 3, 'Edits were queued individually')
h.view('Alice').fail_next_message = true
surfaces['Alice'].handle_command('word_cancel')
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
until remote.call('Watcher').empty?
  raise 'Failed cancellation was never retried' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  pump.call(1)
  sleep 0.001
end
clients.each_value(&:close)
puts 'PASS Scrabble preview: slow native send never blocks edits, bounded coalescing and retry after failure'

# Real model transitions, not just hand-edited revision numbers. Invalid
# words that retain the turn also invalidate the old uncommitted sketch.
[:accepted, :invalid_keep_turn, :timeout, :finished].each do |boundary|
  clients.clear
  options = game.normalize_options('content_language_id' => 'en', 'invalid_word' => '0')
  state = game.initial_state(%w[Alice Bob], options)
  letters = boundary == :invalid_keep_turn ? %w[q x] : %w[c a t]
  rack = letters.map { |face| game.tiles(state).index { |tile| tile[:letter] == face } }
  state.merge!(phase: :playing, current_player: 'Alice', revision: 1, turn: 1, turn_started: 100,
    racks: {'Alice' => rack, 'Bob' => [game.tiles(state).index { |t| t[:letter] == 'e' }]})
  state[:bag] = boundary == :finished ? [] : (60..69).to_a
  state[:turn_deadline] = 101 if boundary == :timeout
  replay = GameRoomGames::Replay.new(players: state[:players], current_player: 'Alice', state: state, history: [])
  %w[Alice Watcher].each { |name| add.call(name) }
  begin
    # A paused fixture clock does not make the real wall-clock surface editable
    # at time 100; deliver the public layout, then apply the actual timeout.
    draft = letters.each_with_index.map { |face, i| [112 + i, face, false] }
    clients['Alice'].draft_changed(draft)
    pump.call
    assert(remote.call('Watcher').size == letters.size, "#{boundary}: preview missing")
    old = Marshal.load(Marshal.dump(h.view('Alice').sent_messages.last))
    data = {'action' => boundary == :timeout ? 'timeout' : 'place', 'revision' => 1, 'time' => 101,
      'placements' => rack.each_with_index.map { |tile, i| [tile, 112+i, game.tiles(state)[tile][:letter]] }}
    status = game.send(:apply, state, data, 'Alice', 999, [])
    assert(status == :ok, "#{boundary}: model transition rejected #{status}")
    clients.each { |name, client| client.before_wait(replay, name); surfaces[name].update_spec(game.surface_spec(replay, name)) }
    h.view('Watcher').deliver_message(h.core.participants.fetch('alice'), old, NativeLiveSessionsBroker::MessageInfo.new)
    pump.call
    assert(remote.call('Watcher').empty?, "#{boundary}: stale draft survived model transition")
    assert(state[:board].compact.size == ([:accepted, :finished].include?(boundary) ? 3 : 0), "#{boundary}: board changed incorrectly")
  ensure
    clients.each_value(&:close)
  end
end
puts 'PASS Scrabble preview: accepted/invalid/timeout/finished model transitions, private messages and restarted author'
