require_relative "../support/native_live_sessions"
require_relative "../../lib/account_saved_games"
require_relative "../support/private_archives"
require_relative "../support/native_room_harness"
require_relative "../../games/four_in_a_row"

h = NativeRoomHarness.new(game: GameRoomGames::FourInARow.new, users: %w[Alice Bob])
h.start
h.write('Alice', [GameRoomGames::EventCommand.new(action: 'drop', value: '3')])
h.write('Bob', [GameRoomGames::EventCommand.new(action: 'drop', value: '4')])
$game_room_test_user = 'Alice'
repo, transport = h.repositories['Alice'], h.transports['Alice']
resources = PrivateArchiveDouble.new
no_disk = Object.new
def no_disk.read_json(*); raise 'Unexpected local save read'; end
def no_disk.update_json(*); raise 'Unexpected local save write'; end
saves = AccountSavedGames.new(no_disk, owner: 'Alice', resources: resources)
boundary = transport.freeze_game(h.session)
snapshot = repo.snapshot_for(h.session, force_events: true)
row = saves.put(game: h.game, table: h.table, snapshot: snapshot, repository: repo, now: boundary.created_at)
before = h.game.replay(snapshot.session, snapshot.events, repo)
transport.deactivate_table(table_id: h.table['__id'])
assert(h.broker.cores.values.first.closed, 'Original Live Session was not closed')

# Another installation sees no local files and resumes into a new native ID.
other_installation = AccountSavedGames.new(no_disk, owner: 'Alice', resources: resources)
archive = other_installation.fetch(other_installation.list.first['id'])
table = transport.create_room(name: 'Resumed', game: h.game.id, owner: 'Alice', game_options: archive['options'], resume_save_id: archive['id'])
bob = GameRoomTransport.new(ProgramDouble.new(h.broker.endpoint('Bob', fresh: true)))
discovered = bob.discover_rooms.first
assert(bob.establish_membership(table_id: table['__id'], owner: 'Alice', capacity: 8, user: 'Bob', table: discovered), 'Remote player could not join new room')
restore = other_installation.restored_data(archive, game: h.game, table_id: table['__id'], now: row['saved_at'] + 86400)
session = repo.restore_session(table: table, game: h.game.id, players: restore[:players], options: row['options'], restore: restore)
assert(session['__id'] != h.session['__id'], 'Archive depends on original native session')
restored = repo.snapshot_for(session, force_events: true)
after = h.game.replay(restored.session, restored.events, repo)
assert(after.board == before.board && after.current_player == before.current_player && after.players == before.players, 'Restoration changed the game')
assert(restored.events.map { |e| repo.event_id(e) } == snapshot.events.map { |e| repo.event_id(e) }, 'Event identities changed')
repo.append_events(session: session, sequence: repo.next_sequence(session, after.accepted_events), actor: 'Alice',
  events: [GameRoomGames::EventCommand.new(action: 'drop', value: '5')])
remote_repo = GameRepository.new(ProgramDouble.new(h.broker.endpoint('Bob')), transport: bob, server_tables: {})
remote_session = remote_repo.session_for_table(discovered)
remote_snapshot = remote_repo.snapshot_for(remote_session)
assert(h.game.replay(remote_snapshot.session, remote_snapshot.events, remote_repo).accepted_events.size == 3, 'Next move did not reach remote replay')
assert(other_installation.list.size == 1, 'Resuming deleted the only saved archive')
transport.deactivate_table(table_id: table['__id'])
other_installation.delete(row['id'])

# Bound decompression by the declared size, reject trailing streams and bad
# checksums; never accept a merely parseable replacement archive.
resources.lost_reply = false
saves.persist(row)
resource = resources.list(timeout: 1).first
original = resources.download(resource.id, timeout: 1)
bad_payloads = [original[0...-1], original + 'trailing', Zlib::Deflate.deflate('x' * 100000)]
bad_payloads.each do |bytes|
  resources.instance_variable_get(:@data)[resource.id] = bytes
  begin
    saves.fetch(row['id'])
    raise 'Invalid compressed archive accepted'
  rescue IOError
  end
end
resources.instance_variable_get(:@data)[resource.id] = original
assert(saves.fetch(row['id']) == row, 'Failed reads modified the original archive')
puts 'PASS account save: original room closed, fresh installation, exact restored replay, remote next move, bounded malformed downloads'
