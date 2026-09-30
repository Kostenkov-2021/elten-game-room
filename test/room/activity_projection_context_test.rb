require_relative "../support/native_room_harness"

h = NativeRoomHarness.new(users: %w[Alice Bob Carol])
h.start
transport = h.transports.fetch('Alice')
store = transport.instance_variable_get(:@live_store)
activity = TableActivityRepository.new(server_tables: {}, transport: transport)
h.as('Alice') do
  20.times { |n| activity.append(table: h.table, kind: 'chat', message: "first #{n}", actor: 'Alice') }
  transport.transfer_room_owner(h.table, 'Bob')
end
new_transport = h.transports.fetch('Bob')
h.as('Bob') do
  new_transport.room_snapshot(h.table)
  10.times do
    current = h.repositories['Bob'].session_for_table(h.table)
    new_transport.replace_game_player(h.table, session_id: current['__id'], player: 'Carol', replacement: nil)
    current = h.repositories['Bob'].session_for_table(h.table)
    bot = current['__players'].find { |person| GameRoomParticipants.bot?(person) }
    assert(bot, 'replacement fixture has no bot')
    row = TableActivityRepository.new(server_tables: {}, transport: new_transport).append(
      table: h.table, kind: 'bot_removed', subject: bot, actor: 'Bob')
    assert(row.subject == bot && row.owner == 'Bob', 'serial bot identity or historical owner lost')
    new_transport.replace_game_player(h.table, session_id: current['__id'], player: bot, replacement: 'Carol')
  end
  20.times { |n| new_transport.append_activity(table: h.table, kind: 'chat', message: "second #{n}", actor: 'Bob') }
end

# Deliberately expensive reference: the former per-record lookup behavior,
# using the production authority validator rather than trusting raw packets.
reference = lambda do
  id = h.table['__id']
  store.send(:ensure_current, id)
  records = store.send(:records_for, id)
  ledger = store.send(:control_ledger, id)
  records.flat_map do |record|
    kind = record.packet['kind']
    if kind == 'room_activity'
      store.send(:activity_record, record)
    elsif kind == GameRoomTableControl::KIND && record.packet['data']['from'].zero?
      data = record.packet['data']
      rows = []
      build = ->(name) { store.send(:lifecycle_activity, record, name,
        ledger: store.send(:control_ledger, id), game: store.send(:table_for, id)['game']) }
      rows << build.call('owner_changed') unless ledger.owner_at(record.sequence - 1).casecmp?(record.sender)
      start = records.find { |r| r.packet['kind'] == 'game_started' && r.packet.dig('data', 'session_id') == data['session_id'] }
      prior = ledger.players(data['session_id'], initial: start&.packet&.dig('data', 'players').to_a, before: record.sequence)
      data.fetch('players', prior).each_with_index do |person, index|
        next if person == prior[index]
        rows << build.call('player_replaced').merge('subject' => prior[index], 'replacement' => person,
          '__id' => record.sequence * GameRoomLiveSessionStore::EVENT_ID_MULTIPLIER + rows.length)
      end
      rows
    end
  end.compact
end
expected = reference.call
calls = 0
original_ledger = store.method(:control_ledger)
store.define_singleton_method(:control_ledger) { |*a, **k| calls += 1; original_ledger.call(*a, **k) }
actual = store.activity_records(h.table)
assert(actual == expected, 'shared activity context changed validated history or authors')
assert(calls <= 2, "ledger rebuilt #{calls} times for #{actual.length} activities")
assert(actual.any? { |r| r['message'].to_s.start_with?("bot:#{h.table['__id']}:10:") }, 'tenth replacement missing')
assert(actual.select { |r| r['message'].to_s.start_with?('first ') }.all? { |r| r['table_owner'] == 'Alice' }, 'old owner rewritten')
assert(actual.select { |r| r['message'].to_s.start_with?('second ') }.all? { |r| r['table_owner'] == 'Bob' }, 'new owner not applied')
puts "PASS activity projection: #{actual.length} entries, ten named replacements, historical authority, #{calls} ledger builds"
