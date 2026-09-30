require_relative "../../support/krowa_services"
require 'date'

tables = KrowaTestTables.new
table = tables.fetch('krowa_daily_completions')
dates = Array.new(1101) { |index| (Date.new(2020, 1, 1) + index).strftime('%Y-%m-%d') }
dates.each { |date| table.insert('day_key' => date.delete('-').to_i, 'status' => 1) }
store = GameRoomGames::KrowaServerStore.new(server_tables: tables, bank: Object.new, user: 'Alice')
2.times { assert(store.synchronize_daily([dates.first, dates[500], dates.last]), 'existing migration failed') }
assert(table.rows.length == 1101, 'migration duplicated a day outside first page')
assert(table.queries.any? { |query| query[:offset] == 1000 && query[:order] == [['__id', 'asc']] }, 'migration did not traverse stable ordered pages')
fresh = Array.new(601) { |index| (Date.new(2026, 1, 1) + index).strftime('%Y-%m-%d') }
assert(store.synchronize_daily(fresh), 'long local migration failed')
assert(fresh.all? { |date| table.rows.any? { |row| row['day_key'] == date.delete('-').to_i } }, 'local migration silently discarded older dates')
before = table.rows.length
assert(store.synchronize_daily(fresh) && table.rows.length == before, 'repeat migration duplicated rows')
missing = ['2030-01-01', '2030-01-02', '2030-01-03']
table.fail_after = 1
begin
  store.synchronize_daily(missing)
  raise 'partial batch did not report failure'
rescue IOError
end
table.fail_after = nil
assert(store.synchronize_daily(missing), 'partial batch retry failed')
assert(missing.all? { |date| table.rows.count { |row| row['day_key'] == date.delete('-').to_i } == 1 }, 'partial retry duplicated committed prefix')
table.define_singleton_method(:select) { |**_options| raise IOError, 'read unavailable' }
before = table.rows.length
begin
  store.synchronize_daily(['2031-01-01'])
  raise 'read failure treated as empty snapshot'
rescue IOError
end
assert(table.rows.length == before, 'migration wrote after failed read')
table.singleton_class.remove_method(:select)
second_device = GameRoomGames::KrowaServerStore.new(server_tables: tables, bank: Object.new, user: 'Alice')
assert(second_device.synchronize_daily(missing) && table.rows.length == before, 'second device repeated already migrated dates')
puts 'Krowa daily migration: 1101 server rows, 601 local dates, ordered pages, partial retry, read failure and second device OK'
