require_relative "../../lib/game_surfaces/specifications"
def _(text)
  text
end

def n_(singular, plural, count)
  count.to_i == 1 ? singular : plural
end

require "json"
require_relative "../../lib/game_random"
require_relative "../../games/base"
require_relative "../../games/card_game"
require_relative "../../content/monopoly_boards"
require_relative "../../games/monopoly"
require_relative "../../games/yahtzee"
require_relative "../../games/uno"
require_relative "../../games/poker"
require_relative "../../games/makao"
require_relative "../../games/biblios"
require_relative "../../games/battleship"
require_relative "../../games/mancala"

class NewGames116Repository
  def initialize(players)
    @players = players
  end

  def players_for(_session)
    @players
  end

  def actor_of(event, _session = nil)
    event.fetch("actor")
  end

  def event_id(event)
    event.fetch("id")
  end
end

class NewGames116Random
  Roll = Struct.new(:values, keyword_init: true)

  def initialize
    @value = 0
  end

  def roll(count:, sides:)
    values = Array.new(count) do
      @value += 1
      ((@value - 1) % sides.to_i) + 1
    end
    Roll.new(values: values)
  end
end

def assert(condition, message)
  raise message if !condition
end

def context_for(random = NewGames116Random.new)
  GameRoomGames::ActionContext.new(random_source: random, now: 1_800_000_000)
end

def append_action(game, session, repository, events, replay, actor, selection, context = nil)
  status, plan = game.action_for(selection, replay, actor, context: context)
  raise "#{game.id} rejected #{selection.inspect}: #{status}" if status != :ok
  plan.events.each do |command|
    events << { "id" => events.length + 1, "actor" => actor, "action" => command.action, "value" => command.value }
  end
  game.replay(session, events, repository)
end
