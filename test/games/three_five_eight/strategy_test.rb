require 'json'
require_relative "../../../lib/game_random"
require_relative "../../../games/three_five_eight"

module ThreeFiveEightStrategyTest
  PLAYERS = %w[Alice Bob Carol].freeze
  GAME = GameRoomGames::ThreeFiveEight.new
  RESULTS = []

  def self.assert(value, message)
    raise message unless value
  end

  def self.check(name)
    yield
    RESULTS << {name: name, status: 'PASS'}
  rescue StandardError => error
    RESULTS << {name: name, status: 'FAIL', error: "#{error.class}: #{error.message}"}
  end

  def self.position(hand, phase: :playing, contract: 'NT', trick: [], events: [], actor: 'Alice')
    state = GAME.send(:initial_state, PLAYERS, GAME.default_options)
    state.update(phase: phase, current_player: actor, chooser: actor, dealer_index: 2,
      contract: contract, round: 1, current_trick: trick,
      hands: PLAYERS.to_h { |player| [player, player == actor ? hand.dup : []] },
      targets: {'Alice' => 8, 'Bob' => 5, 'Carol' => 3})
    GameRoomGames::Replay.new(players: PLAYERS, state: state, current_player: actor, accepted_events: events, history: [])
  end

  def self.choose(replay, seed: 19, game: GAME)
    context = GameRoomGames::ActionContext.new(random_source: GameRoomRandom::SeededSource.new(seed))
    decision = GameRoomBots::Coordinator.new.decide(game: game, replay: replay, actor: replay.current_player,
      context: context, controlled_actors: PLAYERS,
      simulation_factory: -> { raise 'lightweight strategy requested a simulation' })
    assert(decision && decision.available_actions.include?(decision.action), 'decision is not legal')
    [decision.action, context.random_source.roll(count: 1, sides: 1000).values]
  end

  def self.card(replay)
    choose(replay).first['card']
  end

  def self.event(id, actor, card, action = 'play')
    {'id' => id, 'actor' => actor, 'action' => action, 'value' => card}
  end

  def self.run
    check('ordinary wins remain valuable below, at, and above target') do
      [0, 8, 10].each do |taken|
        replay = position(%w[2C AC], trick: [{player: 'Bob', card: 'QC'}, {player: 'Carol', card: 'KC'}])
        replay.state[:tricks]['Alice'] = taken
        assert(card(replay) == 'AC', "gave away certain extra trick at #{taken}")
      end
    end
    check('review position preserves the cheapest winner after target') do
      replay = position(%w[TH QS 3S JS 8H 5D AC TC], contract: 'H',
        trick: [{player: 'Bob', card: '6S'}, {player: 'Carol', card: '8S'}])
      replay.state[:tricks]['Alice'] = replay.state[:targets]['Alice'] = 3
      assert(card(replay) == 'JS', 'did not take a certain extra trick with the cheapest winner')
    end
    check('high balanced six cards select no trump, not forced MISERE') do
      replay = position(%w[AS AH AD AC KS KH], phase: :choosing_contract, contract: nil)
      assert(choose(replay).first['contract'] == 'NT', 'high balanced hand did not choose NT')
    end
    check('long strong suit selects its trump contract') do
      replay = position(%w[AH KH QH JH TH 9H], phase: :choosing_contract, contract: nil)
      assert(choose(replay).first['contract'] == 'H', 'long strong hearts did not choose hearts')
    end
    check('low protected six cards select MISERE') do
      replay = position(%w[2H 3H 2S 3S 2D 2C], phase: :choosing_contract, contract: nil)
      assert(choose(replay).first['contract'] == 'MISERE', 'safe low hand did not choose MISERE')
    end
    check('used contracts are never selected again') do
      replay = position(%w[AS AH AD AC KS KH], phase: :choosing_contract, contract: nil)
      replay.state[:used_contracts]['Alice'] = %w[H S D C NT]
      assert(choose(replay).first['contract'] == 'MISERE', 'last remaining contract was not respected')
    end
    check('MISERE discards a high card instead of its low escape') do
      replay = position(%w[2C AC], phase: :discarding, contract: 'MISERE')
      assert(card(replay) == 'AC', 'threw away the low escape')
    end
    check('MISERE discard considers dangerous short suits and low protection') do
      replay = position(%w[2C 3C 4C 5C AC 9D], phase: :discarding, contract: 'MISERE')
      assert(card(replay) == '9D', 'did not void the unsafe singleton before the protected ace')
    end
    check('ordinary discard preserves trumps and side ace while creating a void') do
      replay = position(%w[2H 3H AH AC 2C 3C 7D], phase: :discarding, contract: 'H')
      assert(card(replay) == '7D', 'did not discard the weak short side suit')
    end
    check('MISERE safely sheds the highest losing card') do
      replay = position(%w[2C KC], contract: 'MISERE',
        trick: [{player: 'Bob', card: 'AC'}, {player: 'Carol', card: 'QC'}])
      assert(card(replay) == 'KC', 'kept the dangerous king instead of the safe two')
    end
    check('MISERE sheds an off-suit ace when void') do
      replay = position(%w[2D AD], contract: 'MISERE',
        trick: [{player: 'Bob', card: 'AC'}, {player: 'Carol', card: 'QC'}])
      assert(card(replay) == 'AD', 'did not shed the off-suit ace')
    end
    check('MISERE leads a safe low card rather than a forced winner') do
      replay = position(%w[2C AC 2D], contract: 'MISERE')
      assert(%w[2C 2D].include?(card(replay)), 'led an avoidable ace in MISERE')
    end
    check('ordinary lead cashes a side ace rather than a low loser') do
      replay = position(%w[2C AC 3D], contract: 'H')
      assert(card(replay) == 'AC', 'did not cash the side ace')
    end
    check('ordinary second hand preserves the higher equivalent winner') do
      replay = position(%w[KC AC 2D], trick: [{player: 'Carol', card: 'QC'}])
      # Alice owns the ace as well, so king and ace are equivalent winners.
      assert(card(replay) == 'KC', 'did not preserve the equivalent higher winner')
    end
    check('publicly played higher cards promote an ordinary winner') do
      events = [event(1, 'Bob', 'AC'), event(2, 'Carol', 'KC'), event(3, 'Alice', '2C')]
      replay = position(%w[QC 2D], events: events)
      assert(card(replay) == 'QC', 'did not cash the promoted queen')
    end
    check('public off-suit play proves only the led-suit void') do
      events = [event(1, 'Alice', '2C'), event(2, 'Bob', '2D'), event(3, 'Carol', '3C')]
      replay = position(%w[AC AH 2H], contract: 'H', events: events)
      context = GAME.bot_decision_context(replay, 'Alice')
      assert(context[:void_suits]['Bob'] == ['C'], 'invented a trump void from optional non-trumping')
      assert(card(replay) == 'AH', 'led an exposed side ace instead of drawing trumps')
    end
    check('exchange requests a missing high suit, not a suit already owned') do
      replay = position(%w[2C AC KC QC JC TC 9C 8C 7C 6C 5C 4C 3C 2D], phase: :exchanging, contract: 'H')
      replay.state.update(exchange_limits: {'Alice' => 1}, exchange_used: {'Alice' => 0}, exchange_targets: {'Bob' => 1})
      action = choose(replay).first
      assert(action['action'] == 'exchange' && action['card'] == '2D', 'requested a high club which cannot exist')
    end
    check('exchange may stop instead of giving up a trump or a master') do
      replay = position(%w[2H AH AC], phase: :exchanging, contract: 'H')
      replay.state.update(exchange_limits: {'Alice' => 1}, exchange_used: {'Alice' => 0}, exchange_targets: {'Bob' => 1})
      assert(choose(replay).first['action'] == 'stop_exchange', 'gave away a trump without a forced improvement')
    end
    check('an unchanged own exchange excludes that target until information changes') do
      events = [event(1, 'Alice', 'Bob|2D', 'exchange')]
      replay = position(%w[2D AC AH], phase: :exchanging, contract: 'H', events: events)
      replay.state.update(exchange_limits: {'Alice' => 3}, exchange_used: {'Alice' => 1}, exchange_targets: {'Bob' => 1, 'Carol' => 1})
      action = choose(replay).first
      assert(action['target'] == 'Carol' && action['card'] == '2D', 'repeated a known fruitless exchange')
      repeated = Marshal.load(Marshal.dump(replay))
      repeated.accepted_events << event(2, 'Alice', 'Carol|2D', 'exchange')
      assert(choose(repeated).first['action'] == 'stop_exchange', 'forgot an earlier unchanged exchange in the same turn')
      new_deal = Marshal.load(Marshal.dump(repeated))
      new_deal.accepted_events << event(3, 'Alice', '2|0|00000000000000000000000000000002', 'deal')
      assert(choose(new_deal).first['action'] == 'exchange', 'carried an exchange rank bound into a new deal')
    end
    check('a later successful exchange cannot prove an earlier unchanged return') do
      # 3D went to Bob for AD; a later 2D offer to Bob brought 3D back.
      # Current ownership of 3D therefore does not prove that the first
      # exchange was unchanged. No previous hidden hand is reconstructed.
      events = [event(1, 'Alice', 'Bob|3D', 'exchange'), event(2, 'Alice', 'Bob|2D', 'exchange')]
      replay = position(%w[3D AD AH], phase: :exchanging, contract: 'H', events: events)
      context = GAME.bot_decision_context(replay, 'Alice')
      assert(context.fetch(:exchange_bounds).fetch('Bob', {}).empty?, 'invented an invalid historical rank bound')
    end
    check('trump exchange return keeps trumps when a weak side card is legal') do
      replay = position(%w[2H KH 3D AC], phase: :exchange_return, contract: 'H')
      replay.state[:pending_exchange] = {giver: 'Bob', target: 'Alice', card: '2H'}
      assert(card(replay) == '3D', 'returned a valuable trump/ace instead of the weak side card')
    end
    check('decisions, tie RNG and observation ignore hidden state in every phase') do
      positions = [position(%w[2C AC 3D]), position(%w[2C AC 3D], phase: :discarding, contract: 'MISERE'),
        position(%w[2H 3H 2S 3S 2D 2C], phase: :choosing_contract, contract: nil)]
      exchange = position(%w[2C AC 3D], phase: :exchanging, contract: 'H')
      exchange.state.update(exchange_limits: {'Alice' => 1}, exchange_used: {'Alice' => 0}, exchange_targets: {'Bob' => 1})
      positions << exchange
      returning = position(%w[2H KH 3D AC], phase: :exchange_return, contract: 'H')
      returning.state[:pending_exchange] = {giver: 'Bob', target: 'Alice', card: '2H'}
      positions << returning
      positions.each do |replay|
        changed = Marshal.load(Marshal.dump(replay))
        changed.state[:hands]['Bob'] = %w[AS KS QS JS]
        changed.state[:hands]['Carol'] = %w[AH KH QH JH]
        changed.state[:complete_hands] = {'Alice' => %w[AS], 'Bob' => %w[2S]}
        changed.state[:kitty] = %w[TS 9S 8S 7S]
        changed.state[:seed] = 'do not use the public seed to recover hidden cards'
        changed.state[:discards] = %w[AD KD QD JD]
        assert(choose(replay) == choose(changed), 'decision or RNG depends on hidden fields')
        assert(GAME.bot_observation(replay, 'Alice') == GAME.bot_observation(changed, 'Alice'), 'observation reveals hidden data')
        GAME.legal_actions(replay, 'Alice').each do |action|
          assert(GAME.bot_action_score(replay, 'Alice', action) == GAME.bot_action_score(changed, 'Alice', action),
            'an action score depends on hidden fields')
        end
      end
    end
    check('public analysis uses projected occupants and stops at the current deal') do
      events = [event(1, 'Alice', '2H'), event(2, 'Bob', '2D'), event(3, 'Carol', '3H'),
        event(4, 'Alice', '2|0|00000000000000000000000000000002', 'deal'),
        event(5, 'Alice', '2C'), event(6, 'OldBob', '2D'), event(7, 'Carol', '3C')]
      replay = position(%w[AC AH 2H], contract: 'H', events: events)
      projected = events.map { |row| row.merge('actor' => row['actor'] == 'OldBob' ? 'Bob' : row['actor']) }
      GameRoomParticipantDecisionEvents.attach(replay, projected)
      before = Marshal.dump(replay.accepted_events)
      context = GAME.bot_decision_context(replay, 'Alice')
      assert(context[:void_suits]['Bob'] == ['C'], 'void was not projected to the current occupant or crossed deals')
      assert(Marshal.dump(replay.accepted_events) == before && replay.accepted_events[5]['actor'] == 'OldBob',
        'analysis changed historical actors')
    end
    check('MISERE forced winner sheds the highest of the winning cards') do
      replay = position(%w[KC AC], contract: 'MISERE',
        trick: [{player: 'Bob', card: '2C'}, {player: 'Carol', card: '3C'}])
      assert(card(replay) == 'AC', 'retained the ace when forced to win')
    end
    check('ordinary unavoidable loss preserves its strongest side card') do
      replay = position(%w[2D AD], trick: [{player: 'Bob', card: 'KC'}, {player: 'Carol', card: 'AC'}])
      assert(card(replay) == '2D', 'threw away an ace on a lost trick')
    end
    check('one context per decision, no simulation, no retained replay cache') do
      game = GameRoomGames::ThreeFiveEight.new
      calls = 0
      game.define_singleton_method(:bot_decision_context) do |*arguments|
        calls += 1
        super(*arguments)
      end
      replay = position(%w[2C 3C 4C 5C 6C 7C 8C 9C TC JC QC KC AC 2D 3D 4D])
      before = Marshal.dump(replay)
      100.times { |seed| choose(replay, seed: seed, game: game) }
      assert(calls == 100, "context built #{calls} times for 100 decisions")
      assert(Marshal.dump(replay) == before, 'decision mutated replay')
      assert(game.instance_variables == [:@bot_strategy], 'strategy retained a replay/cache on the game')
    end
    puts JSON.pretty_generate(results: RESULTS, total: RESULTS.length, failed: RESULTS.count { |result| result[:status] == 'FAIL' })
    exit 1 if RESULTS.any? { |result| result[:status] == 'FAIL' }
  end
end

ThreeFiveEightStrategyTest.run
