require "json"
require_relative "game_random"
require_relative "game_snapshot"
require_relative "game_bots"
require_relative "../games/base"

module GameRoomSimulation
  MatchResult = Struct.new(
    :game_id,
    :players,
    :winner,
    :draw,
    :rewards,
    :events,
    :actions,
    :seed,
    :reason,
    :final_state,
    keyword_init: true
  ) do
    def finished?
      reason == :finished
    end
  end

  class Repository
    attr_reader :players

    def initialize(players)
      @players = GameRoomParticipants.unique(players)
    end

    def players_for(_session)
      @players
    end

    def actor_of(event, _session = nil)
      event.fetch("actor").to_s
    end

    def event_id(event)
      (event["__id"] || event["id"]).to_i
    end
  end

  # A complete game session that uses the production replay and action_for
  # methods but has no dependency on Elten, its UI or the shared server.
  class Environment
    attr_reader :game, :session, :events, :repository, :random_source

    def self.new_game(game:, players:, options: nil, seed: 1)
      normalized = game.normalize_options(options || {})
      session = {
        "__id" => 1,
        "table_id" => 1,
        "game" => game.id,
        "options" => JSON.generate(normalized),
        "__players" => GameRoomParticipants.unique(players)
      }
      new(
        game: game,
        session: session,
        events: [],
        players: players,
        random_source: GameRoomRandom::SeededSource.new(seed),
        seed: seed
      ).tap(&:stabilize!)
    end

    def self.from_snapshot(game:, session:, events:, players:, seed: 1)
      new(
        game: game,
        session: deep_copy(session),
        events: deep_copy(events),
        players: players,
        random_source: GameRoomRandom::SeededSource.new(seed),
        seed: seed
      ).tap(&:stabilize!)
    end

    def self.deep_copy(value)
      GameRoomSnapshot.copy(value)
    end

    def initialize(game:, session:, events:, players:, random_source:, seed: nil)
      @game = game
      @session = session
      @events = events.to_a
      @repository = Repository.new(players)
      @random_source = random_source
      @seed = seed
      @next_event_id = @events.map { |event| @repository.event_id(event) }.max.to_i + 1
      @replay = nil
      @legal_actions_cache = {}
    end

    def initialize_copy(original)
      super
      if original.game.shareable_simulation_snapshot?
        @session = original.session.dup
        @events = original.events.dup
        @replay = original.replay
      else
        @session = self.class.deep_copy(original.session)
        @events = self.class.deep_copy(original.events)
        @replay = nil
      end
      @repository = Repository.new(original.repository.players)
      @random_source = original.random_source.dup
      @legal_actions_cache = original.instance_variable_get(:@legal_actions_cache).to_h.dup
    end

    def fork
      dup
    end

    def fork_for_search
      dup
    end

    def replay
      @replay ||= @game.replay(@session, @events, @repository)
    end

    def players
      @repository.players
    end

    def finished?
      replay.finished?
    end

    def active_actor
      @game.active_actors(replay).first
    end

    def legal_actions(actor = active_actor)
      return [] if actor == nil || finished?

      key = actor.to_s.downcase
      return @legal_actions_cache[key] if @legal_actions_cache.key?(key)

      @legal_actions_cache[key] = @game.legal_actions(replay, actor, context: context).to_a.freeze
    end

    def observation(actor)
      @game.bot_observation(replay, actor)
    end

    def reward(actor)
      @game.bot_reward(replay, actor).to_f
    end

    def step(selection, actor: active_actor)
      return :finished if finished?
      return :no_actor if actor == nil

      before = replay.accepted_events.length
      status, plan = @game.action_for(selection, replay, actor, context: context)
      return status if status != :ok
      return :invalid_plan if !plan.is_a?(GameRoomGames::ActionPlan) || plan.events.to_a.empty?

      append_plan(plan, actor)
      after = replay.accepted_events.length
      return :rejected if after != before + plan.events.length

      stabilize!
      :ok
    end

    # Tree-search games may provide an exact in-memory transition which skips
    # serializing and replaying an event that will never leave this simulation.
    # Normal matches and every real player action continue to use #step.
    def step_for_search(selection, actor: active_actor)
      if @game.respond_to?(:bot_search_transition)
        result = @game.bot_search_transition(
          replay,
          selection,
          actor,
          event_id: @next_event_id,
          context: context
        )
        if result != nil
          status, next_replay = result
          if status == :ok
            @replay = next_replay
            @next_event_id += 1
            @legal_actions_cache = {}
          end
          return status
        end
      end

      step(selection, actor: actor)
    end

    # Runs server-owner actions such as dealing a new hand. A strict bound turns
    # a faulty automatic action into an obvious simulation failure, not a hang.
    def stabilize!
      100.times do
        break if finished?

        automatic = nil
        players.each do |actor|
          selection = @game.automatic_action(replay, actor, context: context)
          next if selection == nil

          automatic = [actor, selection]
          break
        end
        break if automatic == nil

        actor, selection = automatic
        before = replay.accepted_events.length
        status, plan = @game.action_for(selection, replay, actor, context: context)
        break if status != :ok || !plan.is_a?(GameRoomGames::ActionPlan) || plan.events.to_a.empty?

        append_plan(plan, actor)
        break if replay.accepted_events.length != before + plan.events.length
      end
      self
    end

    def context
      GameRoomGames::ActionContext.new(
        session_id: @session["__id"].to_i,
        table_id: @session["table_id"].to_i,
        hidden_submissions: nil,
        random_source: @random_source,
        now: @events.length
      )
    end

    private

    def append_plan(plan, actor)
      appended = []
      plan.events.each do |command|
        event = {
          "id" => @next_event_id,
          "sequence" => @next_event_id,
          "actor" => actor.to_s,
          "action" => command.action.to_s,
          "value" => command.value.to_s
        }
        @events << event
        appended << event
        @next_event_id += 1
      end
      cached = @replay
      @replay = if cached == nil
        nil
      else
        @game.incremental_replay(cached, @session, appended, @repository)
      end
      @legal_actions_cache = {}
    end
  end

end
