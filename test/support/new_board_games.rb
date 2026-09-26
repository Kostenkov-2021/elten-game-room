def _(text)
  text
end

module GameSurfaces
  Piece = Struct.new(:id, :label, :owner, :kind, :value, keyword_init: true)
  Action = Struct.new(:kind, :name, :payload, :source, keyword_init: true) do
    def initialize(kind:, name:, payload: {}, source: nil)
      super(kind: kind, name: name, payload: payload, source: source)
    end
  end
  PieceBoardSpec = Struct.new(
    :id, :width, :height, :header, :pieces, :row_origin, :selectable, :targets,
    :empty_label, :cell_labels, :activation_action, :navigable,
    :navigable_by_coordinate_label_set, :silent_positions_by_coordinate_label_set,
    :silent_sound, :coordinate_label_sets,
    :coordinate_label_names, :default_coordinate_label_set, :default_orientation,
    :orientation_labels, :square_details, :origin_error, :destination_error,
    keyword_init: true
  )
  GridSpec = Struct.new(:width, :height, :header, :cells, :row_origin, keyword_init: true)
  Card = Struct.new(:id, :label, :value, :choices, :shift_choice, :choice_header, keyword_init: true)
  CardZoneSpec = Struct.new(:id, :header, :cards, :empty_label, :hand_order, :hand_epoch, keyword_init: true)
  CardTableSpec = Struct.new(:zones, keyword_init: true)
  Command = Struct.new(:id, :label, :enabled, :payload, keyword_init: true)
  CommandPanelSpec = Struct.new(:commands, keyword_init: true)
  PawnTrackItem = Struct.new(:id, :label, :action, keyword_init: true)
  PawnTrackSpec = Struct.new(:id, :header, :items, :empty_label, :activation_action, :player_labels, keyword_init: true)
  Die = Struct.new(:id, :value, :sides, :held, :label, :enabled, keyword_init: true)
  DiceTraySpec = Struct.new(:id, :header, :dice, :commands, :empty_label, keyword_init: true)
  SurfacePart = Struct.new(:id, :surface, keyword_init: true)
  CompositeSpec = Struct.new(:parts, keyword_init: true)
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
