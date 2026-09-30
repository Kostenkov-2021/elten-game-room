require_relative '../support/native_room_harness'
require_relative '../support/localization'

GameRoomTestLocalization.use_language('en')
h = NativeRoomHarness.new(users: %w[Alice Bob])
transport = h.transports.fetch('Alice')
repo = TableActivityRepository.new(server_tables: {}, transport: transport)
h.as('Alice') do
  transport.append_activity(table: h.table, kind: 'created', actor: 'Alice')
  4.times { |i| transport.append_activity(table: h.table, kind: 'chat', actor: 'Alice', message: "first #{i}") }
end
h.as('Bob') { h.transports['Bob'].append_activity(table: h.table, kind: 'joined', actor: 'Bob') }
h.as('Alice') { transport.append_activity(table: h.table, kind: 'chat', actor: 'Alice', message: 'after join') }
reads, conversions = 0, 0
projection = transport.method(:activity_records)
edit = nil
read_error = false
transport.define_singleton_method(:activity_records) do |table|
  reads += 1
  raise IOError, 'fixture read failure' if read_error
  rows = GameRoomSnapshot.copy(projection.call(table))
  edit&.call(rows)
  rows
end
entry_from = repo.method(:entry_from)
repo.define_singleton_method(:entry_from) { |*args| conversions += 1; entry_from.call(*args) }
original = repo.entries_for(h.table, viewer: 'Alice')
conversions = 0
copy = repo.entries_for(h.table, viewer: 'Alice')
assert(copy == original && conversions.zero? && reads == 2, 'cache bypassed validated read or repeated entry conversion')
copy.first.actor.replace('wrong actor')
copy.find { |entry| entry.kind == 'chat' }.message.replace('wrong text')
copy.clear
assert(repo.entries_for(h.table, viewer: 'Alice') == original, 'returned entries mutated cache/source')
assert(repo.entries_for(h.table, viewer: 'Bob').map(&:kind) == %w[joined chat], 'viewer visit boundary was cached')
assert(repo.entries_for(h.table, limit: 1).map(&:message) == ['after join'], 'requested limit was cached')

# Same length and final ID are insufficient. Correct an earlier projected row
# after the real transport read to exercise the repository's content key.
edit = ->(rows) { rows.find { |row| row['kind'] == 'chat' }['message'] = 'corrected prefix' }
changed = repo.entries_for(h.table)
assert(changed.find { |entry| entry.kind == 'chat' }.message == 'corrected prefix' && conversions == 1, 'earlier correction reused stale entries or rebuilt unchanged rows')
edit = nil
assert(repo.entries_for(h.table) == original, 'restored prefix reused stale entries')
assert(repo.entries_for(h.table.merge('game' => 'different')).empty?, 'table game context reused wrong entries')
assert(repo.entries_for(h.table) == original, 'return to original table context failed')
read_error = true
assert(repo.entries_for(h.table).empty?, 'failed validated read returned cached history')
read_error = false
assert(repo.entries_for(h.table) == original, 'read recovery failed')

edit = ->(rows) { rows.first['table_owner'] = 'Other'; rows.first['__authority_validated'] = false }
assert(repo.entries_for(h.table).none? { |entry| entry.kind == 'created' }, 'changed authority reused a previously valid entry')
edit = nil
assert(repo.entries_for(h.table) == original, 'restored authority reused a rejected entry')

game_entry = Struct.new(:event_id, :text)
games = [game_entry.new(1, 'move one'), game_entry.new(2, 'move two')]
events = [{'id' => 1, '__stack_sequence' => 2}, {'id' => 2, '__stack_sequence' => 20}]
names = ->(id) { "Game #{id}" }
format_calls = 0
format = repo.method(:text_for)
repo.define_singleton_method(:text_for) { |*args, **options| format_calls += 1; format.call(*args, **options) }
merge = -> { repo.merged_history_entries(game_entries: games, game_events: events, activity_entries: original, game_name: names) }
first = merge.call
format_calls = 0
returned = merge.call
assert(returned == first && format_calls.zero?, 'unchanged merge formatted activities again')
returned.first.text.replace('corrupted return')
returned.clear
assert(merge.call == first, 'merged history shared mutable entries')
games.first.text.replace('corrected game prefix')
assert(merge.call.any? { |entry| entry.text == 'corrected game prefix' }, 'same-ID game correction reused stale history')
assert(format_calls.zero?, 'new game history reformatted unchanged chat')
events.first['__stack_sequence'] = 100
assert(merge.call.last.text == 'corrected game prefix', 'corrected event order reused stale merge')
events.first['__stack_sequence'] = 2
original.find { |entry| entry.kind == 'chat' }.message.replace('changed activity prefix')
format_calls = 0
assert(merge.call.any? { |entry| entry.text.include?('changed activity prefix') }, 'same-ID activity correction reused stale merge')
assert(format_calls == 1, 'one edited activity reformatted unchanged chat')

conversions = 0
h.as('Alice') { transport.append_activity(table: h.table, kind: 'chat', actor: 'Alice', message: 'new after cache') }
appended = repo.entries_for(h.table)
assert(appended.last.message == 'new after cache' && conversions == 1, 'new message did not reuse prior validated rows')

GameRoomTestLocalization.use_language('pl')
polish = merge.call
assert(polish.any? { |entry| entry.text == 'Alice utworzył stół.' }, 'language change reused English formatting')
format_calls = 0
GameRoomTestLocalization.use_language('pl')
assert(merge.call == polish && format_calls > 0, 'catalog reload with same language reused old translator')

# Cache inputs must also own nested fields, not only the outer entry Struct.
teams = TableActivityRepository::Entry.new(id: 999, table_id: h.table['__id'], kind: 'options_changed',
  actor: 'Alice', owner: 'Alice', game: 'test', created_at: 1, stack_sequence: 1,
  teams: [%w[Alice Bob], %w[Carol Dave]])
team_merge = -> { repo.merged_history_entries(game_entries: [], game_events: [], activity_entries: [teams], game_name: names) }
previous = team_merge.call
teams.teams.first.first.replace('Changed')
assert(team_merge.call != previous && team_merge.call.first.text.include?('Changed'), 'nested team edit reused stale text')

large = Array.new(TableActivityRepository::PROJECTION_CACHE_LIMIT + 1) { |i| game_entry.new(i, "entry #{i}") }
result = repo.merged_history_entries(game_entries: large, game_events: [], activity_entries: [], game_name: names)
assert(result.length == large.length && repo.instance_variable_get(:@merged_history_projection).nil?, 'cache bound truncated output or retained oversized input')
puts 'PASS activity caches: validated reads, full-prefix/context corrections, visit/limit, language/reload, ordering, nested ownership and bounded retention'
