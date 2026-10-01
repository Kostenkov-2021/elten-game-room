require_relative '../../support/uno_communications_prototype'

include GameRoomTest::Assertions
Proto = UnoCommunicationsFixture::Proto
Harness = UnoCommunicationsFixture::Harness
cases = GameRoomTest::Cases.new

cases.run('only effective reaction options opt into the experiment') do
  game = GameRoomGames::Uno.new
  assert(Proto.mode_for(game: game, options: {}) == :live_sessions, 'Ordinary UNO opted in')
  %w[interceptions straights buzzers].each do |option|
    assert(Proto.mode_for(game: game, options: { option => true }) == :communications, "Missing #{option}")
    assert(Proto.mode_for(game: game, options: { option => false }) == :live_sessions, "Ignored false #{option}")
  end
  assert(Proto.mode_for(game: game, options: { 'super_interceptions' => true }) == :live_sessions, 'Hidden super interceptions enabled transport')
  assert(Proto.mode_for(game: game, options: { 'interceptions' => true, 'super_interceptions' => true }) == :communications, 'Super mode absent')
  assert(Proto.mode_for(game: game, options: { 'deck' => 'flip', 'buzzers' => true }) == :live_sessions, 'Hidden Flip buzzers enabled transport')
  %w[zero_seven draw_responses advanced_responses bluff_challenge draw_until_playable].each do |option|
    assert(Proto.mode_for(game: game, options: { option => true }) == :live_sessions, "Unrelated #{option} enabled transport")
  end
  called = false
  client = Proto::Client.build(game: game, session: { 'options' => '{}' }, viewer: 'Alice',
    endpoint_factory: ->(*) { called = true })
  assert(client.nil? && !called, 'Ordinary UNO opened a channel')
  assert(game.session_runner?, 'Production UNO runner was replaced')
end

cases.run('a native-style endpoint cannot silently claim server ordering') do
  h = Harness.new
  error = nil
  begin
    Proto::Client.new(game: h.game, session: h.session, viewer: 'Alice', endpoint: Object.new)
  rescue Proto::UnsupportedOrdering => failure
    error = failure
  end
  assert(error, 'Unsupported ordering was silently accepted')
end

cases.run('own move waits for server echo, not for a slow master or observer') do
  h = Harness.new(observers: ['Observer'])
  h.deal
  actor = h.replay.current_player
  before = h.replay.state
  selection = h.game.legal_actions(h.replay, actor).first
  assert(h.queue(actor, selection) == :pending, 'Move did not enter the queue')
  assert(h.queue(actor, selection) == :waiting && h.relay.requests.length == 1, 'Rapid Enter duplicated a pending move')
  assert(h.replay.state == before, 'Move was applied optimistically')
  receipt = h.relay.accept
  assert(h.clients[actor].pending?, 'Transport receipt alone unlocked input')
  h.clients[actor].tick
  assert(!h.clients[actor].pending?, 'Own ordered echo did not unlock input')
  assert(h.clients['Observer'].cursor == 1, 'Test observer unexpectedly ran')
  h.settle
  h.consistent!
  assert(receipt.sender == actor, 'The master replaced the original sender')
end

cases.run('server arrival wins competing play/interception in either order') do
  h = Harness.new
  seed, pair = h.find_seed do |replay|
    mover = replay.current_player
    move = h.game.legal_actions(replay, mover).find do |action|
      action['action'] == 'play' && action['card'].match?(/\A[RYGB][0-9]/) && action['card'][1] != replay.state[:discard].last[1]
    end
    intercept = h.players.reject { |player| player == mover }.filter_map do |player|
      action = h.game.legal_actions(replay, player).find { |item| item['interception'] && item['card'].match?(/\A[RYGB][0-9]/) }
      [player, action] if action
    end.first
    [mover, move, *intercept] if move && intercept && h.players[(h.players.index(mover) + 1) % h.players.length] != intercept.first
  end
  [0, 1].each do |first|
    trial = Harness.new
    trial.deal(seed)
    mover, move, interceptor, interception = pair
    assert(trial.queue(mover, move) == :pending && trial.queue(interceptor, interception) == :pending, 'Race was not queued')
    trial.relay.accept(first)
    trial.settle(users: trial.clients.keys.reverse)
    trial.consistent!
    history = trial.replay.history
    if first == 0
      assert(history.any? { |entry| entry.key.start_with?('too_late:') && entry.actor == interceptor }, 'Late interception did not keep its penalty')
      assert(trial.replay.state[:hands][interceptor].include?(interception['card']), 'Late interception removed a card')
    else
      assert(history.any? { |entry| entry.key.start_with?('interception:') && entry.actor == interceptor }, 'First valid interception was lost')
    end
  end
end

cases.run('super interception preserves matching by value across colours') do
  h = Harness.new(options: { 'interceptions' => true, 'super_interceptions' => true })
  seed, pair = h.find_seed do |replay|
    h.players.reject { |player| player == replay.current_player }.filter_map do |player|
      action = h.game.legal_actions(replay, player).find do |item|
        item['interception'] && item['card'][0] != replay.state[:discard].last[0]
      end
      [player, action] if action
    end.first
  end
  h.deal(seed)
  assert(h.queue(*pair) == :pending, 'Super interception was refused')
  h.settle
  h.consistent!
  assert(h.replay.history.any? { |entry| entry.key.start_with?('interception:') && entry.actor == pair.first }, 'Super interception changed its rules')
end

cases.run('each card of a straight stays a separate interruptible move') do
  h = Harness.new(options: { 'straights' => true, 'interceptions' => true })
  seed, pair = h.find_seed do |replay|
    actor = replay.current_player
    action = h.game.legal_actions(replay, actor).find do |item|
      card = item['card'].to_s
      item['action'] == 'play' && card.match?(/\A[RYGB][2-7]/) && replay.state[:hands][actor].any? do |other|
        other[0] == card[0] && other[1].match?(/[0-9]/) && (other[1].to_i - card[1].to_i).abs == 1
      end
    end
    [actor, action] if action
  end
  h.deal(seed)
  actor, first = pair
  h.queue(actor, first)
  h.settle
  next_card = h.game.legal_actions(h.replay, actor).find { |action| action['straight'] }
  assert(next_card, 'The ordinary straight rules lost their continuation')
  assert(h.queue(actor, next_card) == :pending, 'Straight continuation was refused')
  assert(h.clients[actor].cursor == 2, 'Two straight cards became one atomic action')
  h.settle
  h.consistent!
  assert(h.replay.history.any? { |entry| entry.key.start_with?('straight:') }, 'Straight history missing')
end

cases.run('another player can interrupt a straight before its next card reaches the server') do
  h = Harness.new(options: { 'straights' => true })
  seed, choices = h.find_seed do |replay|
    actor = replay.current_player
    first = h.game.legal_actions(replay, actor).find do |item|
      item['action'] == 'play' && item['card'].match?(/\A[RYGB][2-7]/)
    end
    next unless first
    status, plan = h.game.action_for(first, replay, actor, context: h.context)
    next unless status == :ok
    event = GameRoomEventProtocol.normalized(plan.events.first).merge('__id' => 2,
      'actor' => actor, '__insertion_user' => actor, '__authority_user' => h.owner)
    after = h.game.replay(h.session, replay.accepted_events + [event], h.repository)
    continuation = h.game.legal_actions(after, actor).find { |item| item['straight'] }
    next_actor = after.current_player
    other = h.game.legal_actions(after, next_actor).find do |item|
      item['action'] == 'play' && item['card'].match?(/\A[RYGB][0-9]/) &&
        continuation && item['card'][1] != continuation['card'][1]
    end
    [actor, first, continuation, next_actor, other] if continuation && other
  end
  [0, 1].each do |first_arrival|
    trial = Harness.new(options: { 'straights' => true })
    trial.deal(seed)
    actor, first, continuation, next_actor, other = choices
    trial.queue(actor, first)
    trial.settle
    assert(trial.queue(actor, continuation) == :pending, 'Straight was not queued')
    assert(trial.queue(next_actor, other) == :pending, 'Competing card was not queued')
    trial.relay.accept(first_arrival)
    trial.settle
    trial.consistent!
    accepted = trial.replay.history.any? { |entry| entry.key.start_with?('straight:') }
    assert(accepted == first_arrival.zero?, 'Arrival order did not decide interruption of the straight')
    if first_arrival == 1
      assert(trial.replay.state[:hands][actor].include?(continuation['card']), 'Interrupted straight lost its card')
      assert(!trial.clients[actor].pending?, 'Rejected continuation blocked its sender')
    end
  end
end

cases.run('wild choice remains a separate required step') do
  h = Harness.new
  seed, pair = h.find_seed do |replay|
    action = h.game.legal_actions(replay, replay.current_player).find { |item| item['card'].to_s.start_with?('NW') }
    [replay.current_player, action] if action
  end
  h.deal(seed)
  actor, action = pair
  h.queue(actor, action)
  h.settle
  assert(h.replay.state[:colour_choice_player] == actor, 'Wild auto-selected a colour')
  choice = h.game.legal_actions(h.replay, actor).find { |item| item['choice'] == 'B' }
  h.queue(actor, choice)
  h.settle
  h.consistent!
  assert(h.replay.state[:colour] == 'B' && !h.replay.state[:colour_choice_player], 'Chosen colour was not propagated')
end

cases.run('four simultaneous buzzers penalize the last server receipt only once') do
  h = Harness.new(options: { 'buzzers' => true }, players: %w[Alice Bob Carol Dave])
  seed, pair = h.find_seed do |replay|
    action = h.game.legal_actions(replay, replay.current_player).find { |item| item['card'].to_s.start_with?('NB') }
    [replay.current_player, action] if action
  end
  h.deal(seed)
  h.queue(*pair)
  h.settle
  assert(h.replay.state[:buzzer_active], 'Buzzer did not activate')
  before = h.replay.state[:hands].transform_values(&:length)
  h.players.each { |player| assert(h.command(player, 'buzz') == :pending, 'Buzzer press was refused') }
  3.times { h.relay.accept(1) }
  receipt = h.relay.accept
  h.endpoints.each_value { |endpoint| endpoint.push(receipt) }
  h.settle(users: h.players.reverse)
  h.consistent!
  after = h.replay.state[:hands].transform_values(&:length)
  assert(after['Alice'] == before['Alice'] + 2, 'Last server arrival did not draw two')
  assert(h.players.drop(1).all? { |player| after[player] == before[player] }, 'Another player was penalized')
end

cases.run('bot actions use the same stream and an observing master can deal') do
  h = Harness.new(players: ['Alice', 'bot:9:1', 'Carol'], owner: 'Host', observers: ['Observer'])
  seed, = h.find_seed { |replay| replay.current_player == 'bot:9:1' }
  h.deal(seed)
  assert(h.clients['Observer'].submit({ 'kind' => 'command', 'action' => 'draw' }, context: h.context) == :forbidden, 'Observer could play')
  assert(h.command('Alice', 'draw', actor: 'bot:9:1') == :forbidden, 'Human controlled another bot')
  actor = h.replay.current_player
  context = GameRoomGames::ActionContext.new(now: 100, random_source: GameRoomRandom::SeededSource.new(19))
  decision = GameRoomBots::Coordinator.new.decide(game: h.game, replay: h.replay, actor: actor, context: context)
  assert(decision && decision.actor == 'bot:9:1', 'The original strategy did not choose a bot action')
  assert(h.queue('Host', decision.action, actor: actor) == :pending, 'Authorised bot move refused')
  h.settle
  h.consistent!
  assert(h.replay.accepted_events.last['actor'] == actor && h.replay.accepted_events.last['__insertion_user'] == 'Host',
    'Bot command lost its authenticated controller')
end

cases.run('several clients replay a sustained game using only the existing UNO model') do
  [[2, 'classic'], [4, 'classic'], [8, 'classic'], [4, 'no_mercy'], [4, 'flip']].each do |count, deck|
    h = Harness.new(players: Array.new(count) { |index| "Player#{index + 1}" },
      options: { 'deck' => deck, 'interceptions' => true, 'straights' => true, 'buzzers' => deck != 'flip' })
    h.deal(91)
    100.times do |index|
      replay = h.replay
      break if replay.finished?
      actor = replay.state[:colour_choice_player] || replay.current_player || h.players.first
      actor = h.game.active_actors(replay).first if replay.state[:buzzer_active]
      selection = h.game.automatic_action(replay, h.players.first, context: h.context)
      actor = h.players.first if selection
      selection ||= h.game.legal_actions(replay, actor).first
      assert(selection, 'No action to continue the simulation')
      assert(h.queue(actor, selection, context: h.context(seed: index + 200)) == :pending, 'Simulation action refused')
      h.settle(users: h.clients.keys.rotate(index % count))
      h.consistent!
    end
    assert(h.clients.values.first.cursor > 30, 'Too few moves covered')
  end
end

cases.run('thinking-time expiry keeps the ordinary UNO penalty and original deadline') do
  h = Harness.new(options: { 'interceptions' => true, 'thinking_time' => 20 })
  h.deal
  before = h.replay
  deadline = before.state[:turn_deadline]
  assert(deadline > 100, 'The original deal lost its thinking-time deadline')
  assert(h.game.automatic_action(before, h.players.first, context: h.context(now: deadline - 1)).nil?, 'Timeout occurred early')
  selection = h.game.automatic_action(before, h.players.first, context: h.context(now: deadline + 1))
  assert(selection && selection['action'] == 'turn_timeout', 'Existing timeout was not available')
  assert(h.queue(h.owner, selection, context: h.context(now: deadline + 1)) == :pending, 'Timeout was not sent')
  h.settle
  h.consistent!
  assert(h.replay.history.any? { |entry| entry.key.start_with?('timeout:') }, 'The existing timeout penalty disappeared')
end

puts 'PASS local UNO Communications prototype: conditional routing and original rules (simulated relay only)'
