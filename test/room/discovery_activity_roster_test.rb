require_relative "../support/native_live_sessions"

class NativeLiveSessionsBroker::Discovery
  def participants; @core.participants.values.map { |p| {'id'=>p.id, 'user'=>p.user} }; end
  def hide_participants?; false; end
end

broker = NativeLiveSessionsBroker.new
$game_room_test_user = 'Alice'
owner = GameRoomTransport.new(ProgramDouble.new(broker.endpoint('Alice')))
guest = GameRoomTransport.new(ProgramDouble.new(broker.endpoint('Bob')))
reader = GameRoomTransport.new(ProgramDouble.new(broker.endpoint('Carol')))
store = owner.instance_variable_get(:@live_store)
room = owner.create_room(name: 'Roster fixture', game: 'four_in_a_row', owner: 'Alice', game_options: '{}', capacity: 8,
  private_table: false, bot_count: 1, bot_names: ['pl01'])
id = room['__id']
guest.join_room(guest.discover_rooms.first, 'Bob')
owner.set_observer(room, true, actor: 'Alice')
store.publish_discovery(id)
row = reader.discover_rooms.first
roster = reader.discovered_roster(row)
assert(roster[:status] == :ready && roster[:observers] == ['Alice'] && roster[:players].first == 'Bob', 'Owner-observer roster wrong')
assert(GameRoomParticipants.bot_name_token(roster[:players].last) == 'pl01', 'Named bot lost')
assert(broker.endpoint('Carol').sessions.empty?, 'Reading joined the table')
item = row['__discovered_session']
item.define_singleton_method(:hide_participants?) { true }
assert(reader.discovered_roster(row)[:status] == :unavailable, 'Hidden roster leaked')
item.singleton_class.remove_method(:hide_participants?)
item.define_singleton_method(:participants) { nil }
assert(reader.discovered_roster(row)[:status] == :unavailable, 'Unknown roster reported empty')
item.singleton_class.remove_method(:participants)

# Real ELTEN expires discovery tokens even while an unchanged Join list is
# open. Only the exact server expiry permits one fresh public discovery.
module EltenLink
  class Error < StandardError
    attr_reader :code
    def initialize(code); @code = code; super(code); end
  end unless const_defined?(:Error, false)
end
original_refresh = item.method(:refresh)
item.define_singleton_method(:refresh) { |**_| raise EltenLink::Error.new('apps.live_sessions.discovery_expired') }
assert(reader.discovered_roster(row)[:status] == :ready, 'Expired public discovery token was not renewed')
assert(broker.endpoint('Carol').sessions.empty?, 'Renewal joined the session')
item.define_singleton_method(:refresh) { |**_| raise EltenLink::Error.new('permission_denied') }
begin
  reader.discovered_roster(row)
  raise 'Unrelated refusal was swallowed'
rescue EltenLink::Error => error
  assert(error.code == 'permission_denied', 'Unrelated error was replaced')
end
item.define_singleton_method(:refresh, original_refresh)
core = broker.cores.values.first
metadata = core.discovery_metadata
core.discovery_metadata = metadata.merge('roster'=>[1, [['old-id', 0]], []])
assert(reader.discovered_roster(row)[:status] == :unavailable, 'Mismatched membership guessed')
core.discovery_metadata = metadata

session = owner.start_game(table: room, game: 'four_in_a_row', players: ['Bob', roster[:players].last], options: '{}', actor: 'Alice')
owner.update_room(room, {'status'=>'playing'}, actor: 'Alice')
first = store.room_snapshot(room)[:table]['last_activity_at']
assert(first && first > 0, 'Start did not record server activity')
native = store.send(:active_session, id)
count, threads = 0, []
original = native.method(:update_discovery_metadata)
native.define_singleton_method(:update_discovery_metadata) { |*a, **kw| count += 1; threads << Thread.current; original.call(*a, **kw) }
require_relative '../support/server_clock'
clock_before = GameRoomClock.clock
GameRoomClock.instance_variable_set(:@clock, game_room_test_clock { first + 100.0 })
GameRoomClock.clock.synchronize
begin
  # A burst updates only memory and leaves one trailing publication queued.
  100.times { owner.note_realtime_activity(id, session['__id']) }
  store.publish_discovery(id)
  assert(count == 0, 'A burst bypassed the minute limit')
  assert(store.instance_variable_get(:@discovery_due).size == 1, 'Publication queue grew per event')
  assert(native.discovery_metadata['last_activity_at'] == first, 'Marker advanced too early')
  store.instance_variable_get(:@activity_publish_at)[id] = 0
  store.instance_variable_get(:@discovery_due)[id][1] = 0
  store.send(:dispatch_discovery_publication)
  work = store.instance_variable_get(:@discovery_work)
  worker = work
  assert(wait_background_work(worker, timeout: 2), 'Finite discovery worker hung')
  assert(count == 1 && threads.none? { |thread| thread == Thread.current }, 'Activity not published once in the worker')
  assert(native.discovery_metadata['last_activity_at'] == first + 100, 'Last event was lost without another move')
  store.send(:dispatch_discovery_publication)
  assert(count == 1, 'Idle room kept publishing')
  assert(!owner.note_realtime_activity(id, session['__id'] + 1), 'Old/new wrong game could update activity')

  lobby = LobbyRepository.new(ProgramDouble.new(broker.endpoint('Carol')), transport: reader)
  now = GameRoomClock.now.to_i
  assert(lobby.inactive_playing_table?({'status'=>'playing','last_activity_at'=>now - 2700}), '45 minute boundary missed')
  assert(!lobby.inactive_playing_table?({'status'=>'playing','last_activity_at'=>now - 2699}), 'Table hidden early')
  [nil, 0, '100'].each { |stamp| assert(!lobby.inactive_playing_table?({'status'=>'playing','last_activity_at'=>stamp}), 'Legacy unknown age hidden') }
  assert(!lobby.inactive_playing_table?({'status'=>'waiting','last_activity_at'=>1}), 'Waiting table hidden')
ensure
  GameRoomClock.instance_variable_set(:@clock, clock_before)
end

# Accepted chat time only; replaying or merely reading the same history does
# not manufacture a newer timestamp. Arrival/OS time is never used here.
record = GameRoomLiveSessionStore::Record.new(packet: {'kind'=>'room_activity','data'=>{'activity_kind'=>'chat'}}, created_at: first + 300, estimated_time: false)
projected, = store.send(:project_room_records, id, {}, records: [record])
assert(projected['last_activity_at'] == first + 300, 'Chat did not count')
record.estimated_time = true
assert(store.send(:project_room_records, id, {}, records: [record])[0]['last_activity_at'] == nil, 'Estimated receipt time counted')
record.estimated_time = false
record.packet['data']['activity_kind'] = 'joined'
assert(store.send(:project_room_records, id, {}, records: [record])[0]['last_activity_at'] == nil, 'Observer join counted as play')

options = JSON.generate((1..60).to_h { |n| ["option-#{n}", n.to_s * 8] })
large = metadata.merge('game_options'=>options, 'roster'=>[1, Array.new(8) { |i| ['x' * 200 + i.to_s, 0] }, []])
compact = store.send(:compact_discovery, large)
assert(JSON.generate(compact).bytesize <= 1024 && !compact.key?('roster'), 'Optional oversized roster not omitted whole')
assert(store.send(:discovery_options, compact) == options, 'Roster evicted game options')
store.instance_variable_get(:@discovery_due)[id] = [native, 0]
owner.deactivate_table(table_id: id)
store.send(:dispatch_discovery_publication)
assert(count == 1, 'Late publication touched a closed membership')
assert(reader.discovered_roster(row)[:status] == :closed, 'Closed table not distinguished')
puts 'PASS discovery: native roster/no join/privacy/mismatch/bots, server activity, coalesced trailing worker, 45-minute filter, metadata budget and stale membership'
