require_relative "../../support/scientific_war_control"

# The picker starts at a safe boundary. A local bot seals while it is open.
# Use the real UI method, repository and in-memory native-session stack.
f = ScientificWarControlFixture.new
f.app.define_singleton_method(:choose_table_participant) do |*_args|
  f.choose('Alice', f.bot)
  'Bob'
end
f.as('Alice') do
  begin
    f.app.send(:change_table_control, f.table, :transfer_master)
    raise 'Dialog transferred an unrevealed bot envelope'
  rescue GameRoomNetworkErrors::GamePaused
  end
end
assert(f.native.owner?, 'Rejected dialog changed native ownership')
assert(f.replay.state[:commits].key?(f.bot), 'Guard discarded the original bot commitment')

# The owner-leave confirmation uses the same fresh guarded transfer.
f = ScientificWarControlFixture.new
f.app.define_singleton_method(:confirm) do |_question|
  f.choose('Alice', f.bot)
  true
end
f.as('Alice') do
  begin
    f.app.send(:leave_table_from_screen, f.table)
    raise 'Confirmation abandoned an unrevealed bot envelope'
  rescue GameRoomNetworkErrors::GamePaused
  end
end
assert(f.native.owner?, 'Rejected leave lost table ownership')

# A remote old-seat commitment may arrive after the first check but before
# the control record. Its actual stack position, not a guessed revision,
# must reject the candidate before the discovery anchor authenticates it.
f = ScientificWarControlFixture.new(watcher: true)
push = f.native.method(:stack_push)
injected = false
f.native.define_singleton_method(:stack_push) do |packet, **options|
  if packet['kind'] == GameRoomTableControl::KIND && !injected
    injected = true
    f.choose('Bob')
  end
  push.call(packet, **options)
end
f.as('Alice') do
  begin
    f.app.send(:change_table_control, f.table, :replace_player, 'Bob', replacement: 'Watcher')
    raise 'Racing remote commitment was transferred to a different person'
  rescue GameRoomNetworkErrors::GamePaused
  end
end
assert(injected && f.snapshot.session['__players'].include?('Bob'), 'Unsafe replacement changed the authoritative roster')
assert(f.replay.state[:commits].key?('Bob'), 'Rejected replacement lost the committed secret')
assert(f.context('Bob').hidden_submissions.reveal(session_id: f.session['__id'], round_id: 'trick:1', user: 'Bob'), 'Secret was removed')

# Conversely, an action ordered after the control candidate belongs to the
# old controller epoch. It cannot become a commitment owned by the new seat.
f = ScientificWarControlFixture.new(watcher: true)
push = f.native.method(:stack_push)
injected = false
f.native.define_singleton_method(:stack_push) do |packet, **options|
  result = push.call(packet, **options)
  if packet['kind'] == GameRoomTableControl::KIND && !injected
    injected = true
    f.choose('Bob')
  end
  result
end
f.as('Alice') { f.app.send(:change_table_control, f.table, :replace_player, 'Bob', replacement: 'Watcher') }
assert(injected && f.snapshot.session['__players'].include?('Watcher'), 'Safe ordered replacement was not accepted')
assert(f.replay.state[:commits].empty?, 'Late old-epoch secret became the new participant commitment')
assert(f.context('Bob').hidden_submissions.reveal(session_id: f.session['__id'], round_id: 'trick:1', user: 'Bob'), 'Rejected late action deleted its author envelope')

# Another player's already sealed choice does not block a safe individual
# replacement, but the original pending seat and owner transfer stay blocked.
f = ScientificWarControlFixture.new(watcher: true)
f.choose('Alice', f.bot)
replay = f.replay
assert(f.game.participant_replacement_error(replay, player: 'Bob') == nil, 'Uncommitted seat remains blocked')
assert(f.game.participant_replacement_error(replay, player: f.bot, replacement: 'Watcher'), 'Committed bot seat was allowed')
assert(f.game.controller_change_error(replay), 'Pending secret allowed owner transfer')
f.as('Alice') { f.app.send(:change_table_control, f.table, :replace_player, 'Bob', replacement: 'Watcher') }
assert(f.replay.state[:commits].key?(f.bot), 'Safe replacement changed another seat secret')
f.choose('Alice')
f.choose('Watcher')
f.act('Alice', 'Alice', {'kind'=>'command','action'=>'reveal'})
f.act('Watcher', 'Watcher', {'kind'=>'command','action'=>'reveal'})
f.act('Alice', f.bot, {'kind'=>'command','action'=>'reveal'})
assert(f.replay.state[:trick] == 2, 'Safe replacement could not finish the original trick')

# An owner-only transfer does not move a human seat or its private vault. A
# human commit racing *after* the final check remains revealable by its author.
f = ScientificWarControlFixture.new(bots: 0)
transfer = f.native.method(:transfer_ownership)
f.native.define_singleton_method(:transfer_ownership) do |target|
  f.choose('Bob')
  transfer.call(target)
end
f.as('Alice') { f.app.send(:change_table_control, f.table, :transfer_master, 'Bob') }
f.snapshot('Bob') # The new owner authenticates its control checkpoint.
f.choose('Alice')
f.act('Alice', 'Alice', {'kind'=>'command','action'=>'reveal'})
f.act('Bob', 'Bob', {'kind'=>'command','action'=>'reveal'})
assert(f.replay('Bob').state[:trick] == 2, 'Owner transfer stranded an unchanged human seat')

# A terminal aborted match must not lock ownership of its waiting room.
# Its old seats and a merely frozen save boundary remain protected.
f = ScientificWarControlFixture.new(bots: 0, watcher: true)
f.as('Alice') do
  f.app.transport.freeze_game(f.session)
  begin
    f.guard.call
    raise 'A frozen save allowed ownership transfer'
  rescue GameRoomNetworkErrors::GamePaused
  end
  f.app.transport.freeze_game(f.session, frozen: false)
  f.app.transport.abort_game(f.session)
  begin
    f.guard(player: 'Bob', replacement: 'Watcher').call
    raise 'Aborted game seats could be replaced'
  rescue GameRoomNetworkErrors::GamePaused
  end
  assert(f.app.send(:change_table_control, f.table, :transfer_master, 'Bob'), 'Aborted match locked waiting-room ownership')
end
assert(!f.native.owner?, 'Waiting-room ownership was not transferred')

puts 'Scientific War controls: dialog/leave revalidation, ordered remote race, target-only replacement and unchanged human vault OK'
