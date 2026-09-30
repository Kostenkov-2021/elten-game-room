require_relative "../../lib/game_simulation"
require_relative "../../lib/saved_game_archive"
require_relative "../../games/tysiac"
require_relative "../../games/spades"
require_relative "../../games/poker"

def assert(value, message)
  raise message unless value
end

def copy(value)
  Marshal.load(Marshal.dump(value))
end

def off_suit_history(game, players, seed)
  env = GameRoomSimulation::Environment.new_game(game: game, players: players, seed: seed)
  90.times do
    before = env.replay
    actor = env.active_actor
    action = env.legal_actions(actor).find { |item| item['action'] != 'surrender' }
    break unless action
    card = action['card'].to_s.split('|').last
    off_suit = before.state[:phase] == :playing && !before.state[:current_trick].empty? &&
      card.to_s[-1] != before.state[:current_trick].first[:card][-1]
    assert(env.step(action, actor: actor) == :ok, 'legal setup action rejected')
    return [env, actor] if off_suit && env.replay.state[:phase] == :playing && env.replay.state[:round] == before.state[:round]
    break if env.replay.state[:round] != before.state[:round]
  end
  raise 'bounded setup did not find an ordinary off-suit play'
end

def change_roster(game, env, roster)
  boundary = env.events.map { |event| env.repository.event_id(event) }.max.to_i + 1
  changes = env.session.fetch('__seat_changes', []) + [{'id' => boundary, 'players' => roster}]
  session = env.session.merge('__players' => roster, '__initial_players' => env.session.fetch('__initial_players', env.players), '__seat_changes' => changes)
  result = GameRoomSimulation::Environment.new(game: game, session: session, events: copy(env.events), players: roster,
    random_source: GameRoomRandom::SeededSource.new(51))
  result.instance_variable_set(:@next_event_id, boundary + 1)
  result
end

def assert_projection(game, env)
  replay = env.replay
  analysis = GameRoomParticipantDecisionEvents.for(replay)
  assert(replay.accepted_events == env.events, 'accepted historical authors/values changed')
  assert(analysis.length == replay.accepted_events.length, 'analysis dropped accepted events')
  expected = replay.accepted_events.map do |event|
    roster = GameRoomParticipantReplay.roster_at(env.session, env.repository.event_id(event))
    mapping = roster.each_with_index.to_h { |player, i| [player.downcase, replay.players[i]] }
    event.merge('__replay_actor' => mapping.fetch(event['actor'].downcase), 'actor' => mapping.fetch(event['actor'].downcase),
      'value' => game.restored_event_value(event, mapping))
  end
  assert(analysis == expected, 'analysis does not use each event-time seat roster')
  assert(GameRoomParticipantDecisionEvents.for(copy(replay)) == analysis, 'executor snapshot loses analysis view')
end

class DecisionMemoryArchive < GameRoomSavedGameArchive
  private
  def persist(_row); end
end

def archive_round_trip(game, env)
  archive = DecisionMemoryArchive.new(nil, owner: 'Owner')
  snapshot = Struct.new(:session, :events).new(env.session, env.events)
  row = archive.put(game: game, table: {'owner' => 'Owner', 'name' => 'local test'}, snapshot: snapshot,
    repository: env.repository, now: 100)
  original = copy(row)
  assert(row['events'].map { |e| [e['actor'], e['action'], e['value']] } == env.events.map { |e| [e['actor'], e['action'], e['value']] }, 'archive serialized analysis authors')
  restored = archive.restored_data(row, game: game, table_id: 987, now: 200)
  assert(row == original, 'restore modified stored archive')
  session = env.session.merge('__id' => 987, '__players' => restored[:players], '__initial_players' => restored[:initial_players],
    '__seat_changes' => restored[:seat_changes], '__clock_offset' => restored[:clock_offset])
  result = GameRoomSimulation::Environment.new(game: game, session: session, events: restored[:events], players: restored[:players],
    random_source: GameRoomRandom::SeededSource.new(51))
  result.instance_variable_set(:@next_event_id, [*restored[:events].map { |e| e['id'] }, *restored[:seat_changes].map { |e| e['id'] }].max + 1)
  assert_projection(game, result)
  result
end

# Four actual off-suit histories: human/bot and human/observer replacements
# in both model-level directions. Historical people remain in accepted events.
[
  [%w[Alice bot:93:2 bot:93:3], 'bot:91:1'],
  [%w[bot:91:1 bot:91:2 bot:91:3], 'David'],
  [%w[Alice bot:93:2 bot:93:3], 'ObserverDavid'],
  [%w[ObserverDavid bot:93:2 bot:93:3], 'Alice']
].each do |players, replacement|
  game = GameRoomGames::Tysiac.new
  env, departed = off_suit_history(game, players, 1)
  bytes = Marshal.dump(env.events)
  roster = players.map { |p| p == departed ? replacement : p }
  changed = change_roster(game, env, roster)
  assert_projection(game, changed)
  assert(changed.replay.history.map(&:to_h) == env.replay.history.map(&:to_h), 'historical messages changed')
  assert(Marshal.dump(env.events) == bytes, 'source events mutated')
  decision = GameRoomBots::Coordinator.new.decide_next(game: game, replay: changed.replay, context: changed.context)
  assert(decision && changed.legal_actions(decision.actor).include?(decision.action), 'replacement blocks normal bot decision')
  assert(changed.step(decision.action, actor: decision.actor) == :ok, 'continuation rejected')
  # A second replacement after an accepted action requires two mapping epochs.
  returned = change_roster(game, changed, players)
  assert_projection(game, returned)
  restored = archive_round_trip(game, returned)
  actor = restored.active_actor
  TysiacPlanning::Planner.new(game, restored.replay, actor, GameRoomRandom::SeededSource.new(51))
  action = restored.legal_actions(actor).first
  assert(restored.step(action, actor: actor) == :ok, 'post-archive continuation rejected')
end

# The Tysiac remapping contract must map the passed-card recipient as well as
# its author, and must not grant another seat knowledge of a private pass.
game = GameRoomGames::Tysiac.new
env, = off_suit_history(game, %w[Alice Bob Carol], 1)
pass = env.events.find { |event| event['action'] == 'pass_card' }
assert(pass, 'setup has no passed card')
giver = pass['actor']
recipient = pass['value'].split('|').first
mapping = env.players.to_h { |p| [p, p == giver ? 'GiverReplacement' : p == recipient ? 'RecipientReplacement' : p] }
changed = change_roster(game, env, env.players.map { |p| mapping.fetch(p) })
before = TysiacPlanning::Planner.new(game, env.replay, giver, GameRoomRandom::SeededSource.new(51)).send(:known_passed_cards)
after = TysiacPlanning::Planner.new(game, changed.replay, mapping.fetch(giver), GameRoomRandom::SeededSource.new(51)).send(:known_passed_cards)
assert(after == before.to_h { |p,cards| [mapping.fetch(p), cards] }, 'passed-card knowledge lost across both renamed seats')
other = TysiacPlanning::Planner.new(game, changed.replay, mapping.fetch(recipient), GameRoomRandom::SeededSource.new(51)).send(:known_passed_cards)
assert(other.values.all?(&:empty?), 'recipient gained the giver seat private pass analysis')

game = GameRoomGames::Spades.new
env, departed = off_suit_history(game, %w[Alice Bob Carol], 71)
before = game.send(:bot_public_play_context, env.replay)
assert(!before[:void_suits].fetch(departed, []).empty?, 'setup has no known void suit')
changed = change_roster(game, env, env.players.map { |p| p == departed ? 'bot:92:1' : p })
assert_projection(game, changed)
after = game.send(:bot_public_play_context, changed.replay)
assert(after[:void_suits].fetch('bot:92:1') == before[:void_suits].fetch(departed), 'replacement lost void-suit knowledge')
assert(!after[:public_plays].any? { |play| play[:player] == departed }, 'public play analysis retains departed player')
actor = changed.active_actor
assert(changed.step(changed.legal_actions(actor).first, actor: actor) == :ok, 'Spades post-replacement incremental move rejected')
assert_projection(game, changed)
fresh = game.replay(changed.session, changed.events, changed.repository)
assert(game.send(:bot_public_play_context, changed.replay) == game.send(:bot_public_play_context, fresh), 'incremental analysis diverges from full reconstruction')
restored = archive_round_trip(game, changed)
replacement = restored.players.find { |p| GameRoomParticipants.bot?(p) }
assert(game.send(:bot_public_play_context, restored.replay)[:void_suits].fetch(replacement) == before[:void_suits].fetch(departed), 'archive loses current-seat public knowledge')

# Real draw-Poker raise and exchange events: only public raise/count signals
# are retained, under the current seat, including the enabled clock envelope.
game = GameRoomGames::Poker.new
env = GameRoomSimulation::Environment.new_game(game: game, players: %w[Alice Bob Carol],
  options: {'variant' => 'draw', 'thinking_time' => 100}, seed: 71)
raised = false
exchanged = nil
40.times do
  actor = env.active_actor
  actions = env.legal_actions(actor)
  action = if env.replay.state[:phase] == :exchange
    actions.find { |a| JSON.parse(a['cards']).length == 2 }
  elsif !raised
    actions.find { |a| a['action'] == 'raise' } || actions.first
  else
    actions.first
  end
  raised ||= action['action'] == 'raise'
  assert(env.step(action, actor: actor) == :ok, 'Poker setup rejected')
  if action['action'] == 'exchange'
    exchanged = actor
    break
  end
end
assert(raised && exchanged, 'bounded Poker setup lacks raise/exchange')
before = game.send(:poker_public_ranges, env.replay)
raiser = before.keys.find { |key| key.is_a?(String) && before[key] > 0 }
roster = env.players.map { |p| p == exchanged ? 'ExchangeReplacement' : p == raiser ? 'RaiseReplacement' : p }
mapping = env.players.zip(roster).to_h
changed = change_roster(game, env, roster)
assert_projection(game, changed)
after = game.send(:poker_public_ranges, changed.replay)
assert(after.fetch(mapping.fetch(raiser)) == before.fetch(raiser), 'Poker raise signal lost')
assert(after[:exchanges] == before[:exchanges].to_h { |p,count| [mapping.fetch(p), count] }, 'Poker public exchange counts lost or changed')
assert(after[:exchanges].fetch(mapping.fetch(exchanged)) == 2, 'clock envelope corrupts exchange count')
restored = archive_round_trip(game, changed)
assert(game.send(:poker_public_ranges, restored.replay) == after, 'Poker archive changes human-seat analysis')
puts 'Participant decision events: four Tysiac replacement directions/continuations/archives, passed-card privacy, Spades voids and Poker raise/exchange counts'
