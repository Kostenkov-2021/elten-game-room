require_relative "../support/native_room_harness"

# The server may grant a smaller stack packet than the requested 16 KiB.
# This was reproduced on a real 3.0.4 session granting 1536 bytes.
h = NativeRoomHarness.new(users: %w[Alice Bob])
store = h.transports.fetch('Alice').instance_variable_get(:@live_store)
archive = (1..18).map do |id|
  {'id' => id * 100, 'sequence' => id, 'actor' => id.odd? ? 'Alice' : 'Bob',
   'action' => 'play', 'value' => "ż" * 64, 'created_at' => 1000 + id}
end
restore = {events: archive, clock_offset: 0}
h.core.stack_entry_bytes = 1536
session = h.as('Alice') do
  h.repositories.fetch('Alice').restore_session(table: h.table, game: 'test',
    players: h.users, options: '{}', restore: restore)
end
assert(session, 'Negotiated-limit archive was not published')
chunks = h.core.entries.select { |entry| entry['packet']['kind'] == 'game_archive' }
assert(chunks.length > 2, 'Archive ignored the smaller server limit')
assert(chunks.all? { |entry| JSON.generate(entry['packet']).bytesize <= 1536 }, 'Oversized archive chunk')
actual = h.transports.fetch('Bob').game_events(session)
assert(actual.map { |row| row.slice(*archive.first.keys) } == archive, 'Chunking changed or lost archived events')
h.as('Alice') do
  h.repositories.fetch('Alice').append_events(session: session, sequence: 19, actor: 'Alice',
    events: [GameRoomGames::EventCommand.new(action: 'play', value: 'next')])
end
assert(h.transports.fetch('Bob').game_events(session).size == 19, 'No next move after restore')

# Reject unrepresentable rows or too many chunks before checkpoint/import
# writes. Do not silently split a single event or drop roster information.
[[256, 4096, archive], [1536, 9, archive], [1536, 4096,
  [{'id' => 1, 'players' => Array.new(8) { |i| "😀" * 63 + i.to_s }}]]].each do |bytes, entries, records|
  h.core.stack_entry_bytes, h.core.stack_entries = bytes, entries
  before = h.core.entries.length
  begin
    h.as('Alice') { store.start_game(table: h.table, game: 'test', players: h.users, options: '{}',
      actor: 'Alice', restore: {events: records, clock_offset: 0}) }
    raise 'Unrepresentable archive accepted'
  rescue ArgumentError => error
    assert(error.message.include?('too large'), 'Unexpected limit rejection')
  end
  assert(h.core.entries.length == before, 'Rejected archive mutated the live room')
end
puts 'PASS negotiated archive byte/count limits, Unicode, exact remote replay, next move, preflight rejection'
