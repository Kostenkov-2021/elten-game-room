require_relative "../../lib/game_surfaces/specifications"
def _(text)
  text
end


require_relative "../../games/base"
require_relative "../../games/board_game"
require_relative "../../games/reversi"
require_relative "../../games/checkers"
require_relative "../../games/chess"
require_relative "../../games/ludo"
require_relative "../../lib/game_simulation"

class NewGamesRepository
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

class FixedRandomSource
  Roll = Struct.new(:values, keyword_init: true)

  def initialize(*values)
    @values = values.flatten
  end

  def roll(count:, sides:)
    Roll.new(values: @values.shift(count))
  end
end

def assert(condition, message)
  raise message if !condition
end

def append_surface_action(game, session, repository, events, replay, actor, action)
  status, plan = game.action_for(action, replay, actor)
  raise "action rejected: #{status}" if status != :ok
  command = plan.events.first
  events << {
    "id" => events.length + 1,
    "actor" => actor,
    "action" => command.action,
    "value" => command.value
  }
  game.replay(session, events, repository)
end
