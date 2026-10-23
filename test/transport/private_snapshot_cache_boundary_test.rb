require_relative '../support/mille_private'

options = GameRoomGames::MilleBornes::DECK_COUNTS.keys.to_h do |type|
  ["#{type}_cards", type == '25' ? 12 : (type == 'go' ? 1 : 0)]
end.merge('custom_deck' => true, 'include_safeties' => false)
h, runners = MillePrivateTest.create(options: options)
pool_id = h.view('Alice').pools.first.id
MillePrivateTest.move(h, runners, 'Alice', 'draw')
assert(h.view('Alice').pool(pool_id).state['remaining'].zero?, 'fixture pool is not exhausted')
rooms = h.users.to_h do |user|
  store = h.transports.fetch(user).instance_variable_get(:@live_store)
  [user, [store, store.instance_variable_get(:@rooms).fetch(h.table.fetch('__id'))]]
end

reveal = lambda do |user|
  keys = rooms.fetch(user).last.private_draws.keys.select { |account, pool, _| account == user.downcase && pool == pool_id }
  keys.each do |key|
    values = rooms.fetch(user).last.private_draws.fetch(key).reverse
    h.write(user, [GameRoomPrivateCards.command('private_show', 'cache-boundary', operation: 'reveal',
      pool_id: pool_id, draw_id: key.last, values: values)])
  end
end
original = rooms.fetch('Alice').last.private_draws.transform_values(&:dup)
reveal.call('Alice')
h.events('Bob')
h.users.each do |user|
  store, room = rooms.fetch(user)
  # Native disclosure is irreversible even though this artificial attached
  # private_show is not a legal scoring action in the actual Mille model.
  assert(room.verified_pools.key?(pool_id), 'foreign unrevealed hand lost its pool validation cache')
end
reveal.call('Bob')
events = h.events('Bob')

# Isolate the common ordered policy using actual native draw/reveal receipts.
# This is not a claim that Mille itself uses ordered hands.
GameRoomPrivateCards.register('cache_ordered_fixture', ordered: true)
store, room = rooms.fetch('Alice')
ordered = h.session.merge('game' => 'cache_ordered_fixture')
snapshot = store.private_cards_snapshot(ordered, events)
original.each do |key, values|
  assert(snapshot.fetch('__private_draws').fetch(key.last) == values, 'ordered receipt changed to reveal order')
  assert(room.private_draws[key] == values, 'ordered current-round cache was removed')
end
assert(!room.verified_pools.key?(pool_id), 'complete empty pool retained redundant validation cache')

# Do not remove a write not in this prefix or another account's values.
unseen = ['alice', 'unseen-pool', 'pending-draw']
foreign = ['someone-else', pool_id, original.keys.first.last]
room.private_draws[unseen] = [99].freeze
room.private_draws[foreign] = [98].freeze
ordinary = store.private_cards_snapshot(h.session, events)
assert(original.keys.none? { |key| room.private_draws.key?(key) }, 'fully public unordered values remain cached')
assert(room.private_draws[unseen] == [99] && room.private_draws[foreign] == [98], 'cleanup removed an unrelated cache entry')
original.each do |key, values|
  assert(ordinary.fetch('__private_draws').fetch(key.last).sort == values.sort, 'public reconstruction lost cards')
end
before = room.private_draws.dup
store.send(:expire_private_snapshot_cache, h.table['__id'], Object.new, 'Alice',
  {[unseen[1], unseen[2]] => true}, {pool_id => true})
assert(room.private_draws == before, 'old membership expired a replacement cache')

# Public takes are complete evidence without a separate reveal operation.
public_event = {'actor' => 'Alice', '__server_pool' => {'operation' => 'take', 'pool_id' => 'public-pool', 'draw_id' => 'public-draw',
  'count' => 1, 'remaining' => 0, 'visibility' => 'public', 'values' => [1]}}
_, complete = store.send(:private_snapshot_evidence, [public_event])
assert(complete.key?('public-pool'), 'public draw was treated as an unrevealed hand')
public_key = ['alice', 'public-pool', 'public-draw']
room.private_draws[public_key] = [1].freeze
store.private_cards_snapshot(h.session, events + [public_event])
assert(!room.private_draws.key?(public_key), 'public take retained values never used by private snapshot')
runners.each_value(&:close)
puts 'PASS private snapshot cache: native disclosures, foreign hidden hand, ordered draw order, public reconstruction, unseen writes and membership isolation'
