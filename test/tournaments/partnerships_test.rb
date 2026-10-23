require_relative '../../lib/tournaments/partnerships'
require_relative '../support/assertions'
require_relative '../support/elten_array_shuffle'
include GameRoomTest::Assertions
P = GameRoomTournaments::Partnerships
def ledger
  value = P.new
  %w[a b c d e f].each_with_index do |name, index|
    value.apply({'kind'=>'join', '__insertion_user'=>name, '__id'=>index + 1}, organizer: false)
  end
  value
end
def choice(value, action, actor, target, id, key: nil, generation: nil)
  generation ||= P.choice_generation(value.state, actor, target)
  row = {'kind'=>'partnership', 'account'=>actor, 'partner'=>target,
    'pairing_generation'=>generation, '__insertion_user'=>actor, '__id'=>id,
    'operation_key'=>"request-#{id}", 'amendment_json'=>JSON.generate({'version'=>1, 'action'=>action, 'request_key'=>key})}
  value.apply(row, organizer: actor == 'a')
  row
end
value = ledger
old = choice(value, 'request', 'a', 'b', 10)
choice(value, 'request', 'a', 'c', 11)
assert_equal('c', value.requests.fetch('a').fetch('to'))
assert_equal(1, value.requests.size)
choice(value, 'accept', 'b', 'a', 12, key: old['operation_key'])
assert_equal({}, value.links, 'Old notification accepted a replaced proposal')
request = value.requests.fetch('a').fetch('key')
choice(value, 'accept', 'c', 'a', 13, key: request)
assert_equal({'a'=>'c', 'c'=>'a'}, value.links)
choice(value, 'request', 'a', 'd', 14)
assert_equal({}, value.requests, 'Established team was dissolved by a new invitation')
choice(value, 'dissolve', 'a', 'c', 15)
assert_equal({}, value.links)
choice(value, 'request', 'b', 'c', 16)
choice(value, 'decline', 'c', 'b', 17, key: 'request-16')
assert_equal({}, value.requests)
assert(value.changes.any? { |row| row['kind'] == 'declined' })
choice(value, 'request', 'd', 'e', 18)
choice(value, 'cancel', 'd', nil, 19, key: 'request-18')
assert_equal({}, value.requests)

# Independent readers and repeated draw events agree, preserve chosen pairs,
# close pending requests and cannot draw the same roster a second time.
choice(value, 'request', 'a', 'b', 20)
choice(value, 'accept', 'b', 'a', 21, key: 'request-20')
choice(value, 'request', 'c', 'f', 22)
draw = {'kind'=>'pair_draw', 'account'=>'a', 'partner'=>nil,
  'pairing_generation'=>value.draw_generation, '__insertion_user'=>'a', '__id'=>23,
  'operation_key'=>'draw-23', 'amendment_json'=>JSON.generate({'version'=>1, 'seed'=>'a' * 64})}
before = Marshal.dump(value)
copy = Marshal.load(before)
value.apply(draw, organizer: true)
copy.apply(draw, organizer: true)
assert_equal(copy.state, value.state)
assert_equal('b', value.links['a'])
assert_equal(6, value.links.size)
assert_equal({}, value.requests)
after = value.state
value.apply(draw.merge('__id'=>24, 'operation_key'=>'draw-again'), organizer: true)
assert_equal(after, value.state)

# Epoch changes invalidate delayed decisions even if the names are identical.
value = ledger
request = choice(value, 'request', 'a', 'b', 30)
stale = P.choice_generation(value.state, 'b', 'a')
value.apply({'kind'=>'withdrawal', '__insertion_user'=>'b', '__id'=>31, 'operation_key'=>'left-31'}, organizer: false)
value.apply({'kind'=>'join', '__insertion_user'=>'b', '__id'=>32}, organizer: false)
choice(value, 'accept', 'b', 'a', 33, key: request['operation_key'], generation: stale)
assert_equal({}, value.links)
puts 'PASS partnership ledger: exact consent, replacement, dissolution, decline/cancel, one draw, chosen pairs, epochs and ELTEN shuffle'
