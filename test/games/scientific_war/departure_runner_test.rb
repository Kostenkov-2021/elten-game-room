require_relative "../../support/scientific_war_control"

# Bot choices are held only by the current master. An uncommitted departed
# human can be replaced without changing those envelopes or other humans.
game = GameRoomGames::ScientificWar.new
h = NativeRoomHarness.new(game: game, users: %w[Alice Bob Carol], bots: 1,
  options: game.default_options.merge('bot_delay' => 0))
h.start
master = runner_for(h, 'Alice')
tick = 0.0
master.instance_variable_get(:@turn).instance_variable_set(:@clock, -> { tick })
3.times { tick += 2; step(h, master, 'Alice') }
before = h.replay('Alice')
original_bot = before.players.last
commitment = before.state[:commits].fetch(original_bot)
h.as('Bob') { h.view('Bob').leave }
h.as('Carol') { h.view('Carol').leave }
8.times { tick += 2; step(h, master, 'Alice') }
current = h.repositories['Alice'].snapshot_for(h.session)
replay = game.replay(current.session, current.events, h.repositories['Alice'])
assert(replay.players[1..2].all? { |player| GameRoomParticipants.bot?(player) }, 'Not all uncommitted departed places were replaced')
assert(replay.state[:commits][original_bot] == commitment, 'Original bot secret was replaced or discarded')
assert(replay.state[:commits].size == 3, 'Replacement bots could not seal their cards')
h.as('Alice') do
  action = game.legal_actions(replay, 'Alice').find { |item| item['action'] == 'select' }
  assert(master.submit(session: current.session, replay: replay, selection: action, actor: 'Alice').first == :ok, 'Remaining human could not choose')
end
12.times { tick += 2; step(h, master, 'Alice') }
assert(h.replay('Alice').state[:trick] >= 2, 'Original trick could not finish after two replacements')
master.close

# Conversely, a departed human who already sealed a card still owns a secret.
# The master cannot invent its reveal or replace the place even if other
# places are safely replaceable at the same time.
h = NativeRoomHarness.new(game: game, users: %w[Alice Bob Carol], options: game.default_options.merge('bot_delay' => 0))
h.start
bob = runner_for(h, 'Bob')
step(h, bob, 'Bob')
assert(submit(h, bob, 'Bob').first == :ok, 'Bob could not seal a card')
commitment = h.replay('Alice').state[:commits].fetch('Bob')
h.as('Bob') { h.view('Bob').leave }
h.as('Carol') { h.view('Carol').leave }
master = runner_for(h, 'Alice')
8.times { step(h, master, 'Alice') }
replay = h.replay('Alice')
assert(replay.players.include?('Bob') && !replay.players.include?('Carol'), 'Target-aware policy lost the pending human or kept the safe departure')
assert(replay.state[:commits]['Bob'] == commitment, 'Pending human commitment changed')
assert(!replay.state[:reveals].key?('Bob'), 'Master invented the absent human reveal')
master.close
bob.close

puts 'Scientific War runner: multiple safe departures continue play; unrevealed departed human remains protected OK'
