require_relative 'cases'
require_relative 'elten_array_shuffle'
require_relative '../../tools/uno_communications/simulated_relay'

module UnoCommunicationsFixture
  Proto = GameRoomUnoCommunicationsPrototype

  class SeedSource
    attr_reader :calls
    def initialize(seed); @seed, @calls = seed, 0; end
    def roll(count:, sides:)
      raise 'Unexpected UNO seed request' unless count == 16 && sides == 256
      @calls += 1
      GameRoomRandom::Roll.new(values: format('%032x', @seed).scan(/../).map { |pair| pair.to_i(16) + 1 })
    end
  end

  class Harness
    attr_reader :game, :session, :repository, :relay, :clients, :endpoints, :players, :owner
    def initialize(options: { 'interceptions' => true }, players: %w[Alice Bob Carol], owner: players.first,
        observers: [], match: 7, epoch: 'first')
      @game, @players, @owner = GameRoomGames::Uno.new, players, owner
      @session = { '__id' => match, 'table_id' => 9, '__control_epoch' => epoch, '__table_owner' => owner,
        '__players' => players, 'options' => JSON.generate(@game.normalize_options(options)) }
      @repository = GameRepository.new(nil, transport: Object.new)
      @relay, @endpoints, @clients = Proto::SimulatedRelay.new, {}, {}
      users = (players.reject { |player| GameRoomParticipants.bot?(player) } + observers + [owner]).uniq
      users.each { |user| add(user) }
    end

    def add(user)
      @clients[user] = Proto::Client.build(game: @game, session: @session, viewer: user, repository: @repository,
        endpoint_factory: lambda do |identity, viewer|
          @endpoints[user] = @relay.endpoint(identity, viewer)
        end)
    end

    def context(seed: 1, now: 100)
      GameRoomGames::ActionContext.new(now: now, random_source: SeedSource.new(seed))
    end

    def queue(user, selection, actor: user, controller: false, context: self.context)
      @clients.fetch(user).submit(selection, actor: actor, controller: controller, context: context)
    end

    def play(user, card, actor: user)
      queue(user, { 'kind' => 'card', 'action' => 'select', 'card_id' => card }, actor: actor)
    end

    def command(user, action, **options)
      queue(user, { 'kind' => 'command', 'action' => action }, **options)
    end

    def settle(users: @clients.keys)
      @relay.accept until @relay.requests.empty?
      users.each { |user| @clients.fetch(user).tick }
    end

    def deal(seed = 1)
      status = command(@owner, 'deal', actor: @players.first, controller: @owner != @players.first,
        context: context(seed: seed))
      raise "Deal was not sent: #{status}" unless status == :pending
      settle
    end

    def replay(user = @owner); @clients.fetch(user).replay; end

    def consistent!
      raise 'Divergent ordered events' unless @clients.values.map(&:events).uniq.one?
      raise 'Divergent replay states' unless @clients.values.map { |client| client.replay.state }.uniq.one?
      raise 'Divergent history' unless @clients.values.map { |client| client.replay.history }.uniq.one?
      actual = replay
      baseline = @game.replay(@session, @clients.values.first.events, @repository)
      raise 'The prototype differs from ordinary UNO replay' unless actual == baseline
    end

    # Real deterministic deals, not a replacement UNO model or patched rules.
    # Fixture predicates only locate a hand suitable for a particular test.
    def find_seed
      2_000.times do |seed|
        event = { '__id' => 1, 'actor' => @players.first, '__insertion_user' => @owner,
          '__authority_user' => @owner, '__controller' => @owner != @players.first,
          'action' => 'deal', 'value' => "1|#{seed % @players.length}|#{format('%032x', seed)}|0" }
        candidate = @game.replay(@session, [event], @repository)
        result = yield(candidate)
        return [seed, result] if result
      end
      raise 'No suitable real UNO deal found within the bounded seed search'
    end

    def packet(user, command, actor: user, controller: false, round: replay.state[:round])
      JSON.generate('version' => 1, 'round' => round, 'actor' => actor,
        'controller' => controller, 'command' => command)
    end
  end
end
