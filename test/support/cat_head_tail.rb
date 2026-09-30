require_relative "../../lib/game_surfaces/specifications"
def _(text)
  text
end


require "json"
require_relative "../../lib/game_random"
require_relative "../../games/base"
require_relative "../../games/cat_head_tail"

class CatHeadTailRepository
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

def assert(condition, message)
  raise message if !condition
end

def cht_event(id, actor, action, value = "")
  { "id" => id, "actor" => actor, "action" => action, "value" => value.to_s }
end

def cht_replay(game, players, events, score_limit: 100)
  repository = CatHeadTailRepository.new(players)
  session = { "options" => JSON.generate(game.normalize_options("score_limit" => score_limit)) }
  [game.replay(session, events, repository), repository, session]
end
