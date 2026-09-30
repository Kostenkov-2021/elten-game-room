require_relative "../support/native_live_sessions"
require_relative "../../lib/account_saved_games"
require_relative "../support/private_archives"
require_relative "../support/native_room_harness"
require_relative "../../games/four_in_a_row"
h = NativeRoomHarness.new(game: GameRoomGames::FourInARow.new, users: %w[Alice Bob])
h.start
h.write('Alice',[GameRoomGames::EventCommand.new(action:'drop',value:'3')])
$game_room_test_user = 'Alice'
transport, repo = h.transports['Alice'], h.repositories['Alice']
transport.set_seat_controller(h.table, session_id:h.session['__id'],seat:'Bob',bot:true)
session = repo.session_for_table(h.table)
archive_store = AccountSavedGames.new(Object.new,owner:'Alice',resources:PrivateArchiveDouble.new)
row = archive_store.put(game:h.game, table:h.table, snapshot:repo.snapshot_for(session), repository:repo)
old_bot = row['players'].last
assert(GameRoomParticipants.bot?(old_bot) && row['seat_changes'].last['players'] == row['players'], 'Archive lost the real replacement')
transport.deactivate_table(table_id:h.table['__id'])
table = transport.create_room(name:'Restored controls',game:h.game.id,owner:'Alice',game_options:row['options'],
  bot_count: 1, bot_names: [GameRoomParticipants.bot_name_token(old_bot)])
data = archive_store.restored_data(row,game:h.game,table_id:table['__id'])
restored = repo.restore_session(table:table,game:h.game.id,players:data[:players],options:row['options'],restore:data)
bot = restored['__players'].last
assert(GameRoomParticipants.bot?(bot) && restored['__initial_players'] == %w[Alice Bob], 'Restoration lost replacement history')
replay = h.game.replay(restored,repo.snapshot_for(restored).events,repo)
assert(replay.current_player==bot, 'Saved turn changed')
repo.append_events(session:restored,sequence:repo.next_sequence(restored,replay.accepted_events),actor:bot,
  events:[GameRoomGames::EventCommand.new(action:'drop',value:'4')])
assert(repo.snapshot_for(restored).events.size==2, 'Restored bot could not move')
assert(replay.history.first.text.include?('Bob'), 'Archived history lost its original participant')

# Several changes interleaved with real moves remain restorable, even if a
# old archive contains an occupied-place exchange from the earlier interface.
bob = GameRoomTransport.new(ProgramDouble.new(h.broker.endpoint('Bob', fresh: true)))
bob.join_room(table, 'Bob')
transport.replace_game_player(table, session_id: restored['__id'], player: bot, replacement: 'Bob')
fresh = repo.snapshot_for(restored)
repo.append_events(session: fresh.session, sequence: repo.next_sequence(fresh.session, fresh.events), actor: 'Alice',
  events: [GameRoomGames::EventCommand.new(action: 'drop', value: '5')])
transport.instance_variable_get(:@live_store).send(:publish_control, table['__id'], restored['__id'], {}, players: %w[Bob Alice])
fresh = repo.snapshot_for(restored)
replaced = h.game.replay(fresh.session, fresh.events, repo)
assert(replaced.current_player == 'Alice', 'Playing-player swap changed whose place must move')
repo.append_events(session: fresh.session, sequence: repo.next_sequence(fresh.session, fresh.events), actor: 'Alice',
  events: [GameRoomGames::EventCommand.new(action: 'drop', value: '6')])
before = repo.snapshot_for(restored)
before_replay = h.game.replay(before.session, before.events, repo)
multiple = archive_store.put(game: h.game, table: table, snapshot: before, repository: repo)
transport.deactivate_table(table_id: table['__id'])
another = transport.create_room(name: 'Multiple replacements', game: h.game.id, owner: 'Alice', game_options: multiple['options'])
bob.join_room(another, 'Bob')
data = archive_store.restored_data(multiple, game: h.game, table_id: another['__id'])
again = repo.restore_session(table: another, game: h.game.id, players: data[:players], options: multiple['options'], restore: data)
after = repo.snapshot_for(again)
after_replay = h.game.replay(after.session, after.events, repo)
assert(after_replay.board == before_replay.board && after_replay.current_player == before_replay.current_player, 'Multiple restored replacements changed the game')
assert(after_replay.history.map(&:text) == before_replay.history.map(&:text), 'Repeated restoration rewrote historical people')
assert(after_replay.accepted_events.size == before_replay.accepted_events.size, 'An archived move was lost')

# Eight maximal Unicode names would overflow a fixed ten-row archive chunk.
store = GameRoomLiveSessionStore.allocate
large_players = (0...8).map { |i| "\u{1f600}" * 63 + i.to_s }
archive = (1..20).map { |id| {'id' => id, 'players' => large_players} }
chunks = store.send(:archive_chunks, archive, archive_id: 'a' * 36, actor: 'Alice')
assert(chunks.length > 2 && chunks.flatten(1) == archive, 'Large replacement archive was not split safely')
chunks.each_with_index do |events, index|
  bytes = JSON.generate({'version' => 2, 'kind' => 'game_archive', 'actor' => 'Alice',
    'data' => {'archive_id' => 'a' * 36, 'index' => index, 'events' => events}}).bytesize
  assert(bytes <= GameRoomLiveSessionStore::STACK_ENTRY_BYTES, 'Replacement archive exceeds native byte limit')
end
puts 'Save/restore retains an actual named bot and earlier human history without requiring the departed human login: OK'
