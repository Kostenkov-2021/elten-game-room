require_relative "../../lib/game_surfaces/specifications"
require_relative "new_games_fixture"
require_relative "elten_array_shuffle"
require_relative "../../games/tysiac"

module GameSurfaces
  unless const_defined?(:QuestionSpec)


  end
end

class TwoPlayerTysiacFixture
  attr_reader :game, :session, :repository, :events, :players

  def initialize(size: 3, award: true)
    @game = GameRoomGames::Tysiac.new
    @players = %w[Alice Bob]
    @repository = NewGames116Repository.new(players)
    @session = { "options" => JSON.generate(game.normalize_options(
      "variant" => "two_players", "talon_size" => size.to_s, "last_trick_talon" => award
    )) }
    @events = []
  end

  def replay
    game.replay(session, events, repository)
  end

  def event(actor, action, value)
    events << { "id" => events.length + 1, "actor" => actor, "action" => action, "value" => value.to_s }
    replay
  end

  def move(selection, actor: replay.current_player)
    status, plan = game.action_for(selection, replay, actor, context: context_for)
    assert(status == :ok, "rejected #{selection}: #{status}")
    before = replay.accepted_events.length
    plan.events.each { |command| event(actor, command.action, command.value) }
    assert(replay.accepted_events.length == before + plan.events.length, "replay rejected action")
    replay
  end

  def deal
    event("Alice", "deal", "1|0|000102030405060708090a0b0c0d0e0f")
  end

  def auction
    deal
    move({ "kind" => "command", "action" => "bid", "bid" => 100 })
    move({ "kind" => "command", "action" => "bid", "bid" => "pass" })
  end

  def choose(index = 0)
    move({ "kind" => "question", "action" => "submit", "question_id" => "choose_talon", "answer" => index.to_s })
  end

  def discard
    card = replay.state[:hands][replay.current_player].first
    move({ "kind" => "card", "action" => "select", "card" => card })
    card
  end
end
