require_relative '../../lib/tournaments/participant_rows'
require_relative '../support/assertions'
include GameRoomTest::Assertions
members = %w[a b c d e f].map { |name| {'account'=>name, 'username'=>name.upcase} }
groups = [{'accounts'=>%w[b a]}, {'accounts'=>%w[d e f]}]
rows = GameRoomTournaments::ParticipantRows.build(members, groups)
assert_equal([%w[a b], %w[d e f], ['c']], rows.map { |row| row['accounts'] })
assert_equal(members.map { |row| row['account'] }.sort, rows.flat_map { |row| row['accounts'] }.sort)
assert_equal(6, rows.flat_map { |row| row['accounts'] }.uniq.length)
assert_equal(rows.map { |row| row['key'] }, GameRoomTournaments::ParticipantRows.build(members.reverse, groups.reverse).map { |row| row['key'] })
assert_equal([], GameRoomTournaments::ParticipantRows.build([], []))
assert_equal(6, GameRoomTournaments::ParticipantRows.build(members, []).length)
puts 'PASS one participant list: each team once, arbitrary team sizes, unpaired people below, stable keys and no synthetic users'
