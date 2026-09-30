require "json"
require_relative "base"
require_relative "../lib/board_presentation"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  # A complete, legal move exposed by a turn-based board game.  The shared
  # board surface only needs the origin and destination; rule-specific data
  # remains in metadata and is serialized with the server event.
  BoardMove = Struct.new(:from, :to, :metadata, :label, keyword_init: true) do
    def initialize(from:, to:, metadata: {}, label: nil)
      super(
        from: from.to_a.map(&:to_i).freeze,
        to: to.to_a.map(&:to_i).freeze,
        metadata: metadata.to_h.transform_keys(&:to_s).freeze,
        label: label == nil ? nil : label.to_s
      )
    end

    def action
      {
        "kind" => "piece_board",
        "action" => "move",
        "from_x" => from[0],
        "from_y" => from[1],
        "to_x" => to[0],
        "to_y" => to[1]
      }.merge(metadata)
    end

    def event_value
      coordinates = "#{from[0]},#{from[1]}>#{to[0]},#{to[1]}"
      additions = metadata.map { |key, value| "#{key}=#{value}" }
      ([coordinates] + additions).join(";")
    end
  end

  # Shared adapter between rule engines and the existing accessible piece
  # board.  Games still own their rules; this class standardizes selection,
  # validation and the wire representation of moves.
  class TurnBasedBoardGame < Base
    include GameRoomBoardPresentation

    def legal_actions(replay, actor, context: nil)
      return [] if replay.finished? || !same_user?(replay.current_player, actor)

      available_board_moves(replay, actor).map(&:action)
    end

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      return [:not_your_turn, nil] if !same_user?(replay.current_player, actor)
      return [:invalid, nil] if selection["kind"].to_s != "piece_board"
      return [:invalid, nil] if selection["action"].to_s != "move"

      from = [selection_value(selection, "from_x"), selection_value(selection, "from_y")]
      to = [selection_value(selection, "to_x"), selection_value(selection, "to_y")]
      candidates = available_board_moves(replay, actor).select do |move|
        move.from == from && move.to == to
      end
      return [:invalid_move, nil] if candidates.empty?

      move = candidates.find do |candidate|
        candidate.metadata.all? do |key, value|
          !selection.respond_to?(:key?) || !selection.key?(key) || selection[key].to_s == value.to_s
        end
      end || candidates.first
      [:ok, event_plan(board_event_action, move.event_value)]
    end

    def board_event_action
      "move"
    end

    def move_error(status)
      return _("This move is not legal in the current position.") if status == :invalid_move

      super
    end

    def build_piece_board(
      replay,
      viewer,
      width:,
      height:,
      pieces:,
      moves:,
      id: self.id,
      cell_labels: nil,
      activation_action: nil,
      navigable: nil,
      navigable_by_coordinate_label_set: nil,
      silent_positions_by_coordinate_label_set: nil,
      silent_sound: nil,
      coordinate_label_sets: nil,
      coordinate_label_names: nil,
      default_coordinate_label_set: nil,
      default_orientation: nil,
      orientation_labels: nil,
      square_details: nil,
      origin_error: nil,
      destination_error: nil
    )
      allowed = !replay.finished? && same_user?(replay.current_player, viewer) ? moves : []
      targets = allowed.group_by(&:from).transform_values { |items| items.map(&:to).uniq }
      origin_error ||= lambda do |position, field, piece, labeler|
        board_origin_error(
          replay,
          viewer,
          position,
          field: field,
          piece: piece,
          labeler: labeler
        )
      end
      destination_error ||= lambda do |origin, destination, origin_field, destination_field, piece, target, labeler|
        board_destination_error(
          replay,
          viewer,
          origin,
          destination,
          origin_field: origin_field,
          destination_field: destination_field,
          piece: piece,
          target: target,
          labeler: labeler
        )
      end
      GameSurfaces::PieceBoardSpec.new(
        id: id,
        width: width,
        height: height,
        header: game_field_header(replay, viewer),
        pieces: pieces,
        row_origin: :bottom,
        selectable: targets.keys,
        targets: targets,
        empty_label: "",
        cell_labels: cell_labels,
        activation_action: activation_action,
        navigable: navigable,
        navigable_by_coordinate_label_set: navigable_by_coordinate_label_set,
        silent_positions_by_coordinate_label_set: silent_positions_by_coordinate_label_set,
        silent_sound: silent_sound,
        coordinate_label_sets: coordinate_label_sets,
        coordinate_label_names: coordinate_label_names,
        default_coordinate_label_set: default_coordinate_label_set,
        default_orientation: default_orientation,
        orientation_labels: orientation_labels,
        square_details: square_details,
        origin_error: origin_error,
        destination_error: destination_error
      )
    end

    def board_origin_error(replay, actor, _position, field:, piece:, labeler:)
      contextual = board_selection_context_error(replay, actor, field: field, piece: piece)
      return contextual if contextual != nil

      _("Your %{piece} on %{field} has no legal move in the current position.") % {
        piece: piece.label.to_s,
        field: field
      }
    end

    def board_destination_error(
      replay,
      actor,
      _origin,
      _destination,
      origin_field:,
      destination_field:,
      piece:,
      target:,
      labeler:
    )
      contextual = board_turn_error(replay, actor)
      return contextual if contextual != nil
      if target != nil && same_user?(target.owner, actor)
        return _("Field %{field} is occupied by your %{piece}.") % {
          field: destination_field,
          piece: target.label.to_s
        }
      end
      if target != nil
        return _("The selected piece cannot capture %{piece} on %{field} with this move.") % {
          piece: target.label.to_s,
          field: destination_field
        }
      end

      _("You cannot move the selected piece from %{from} to %{to}. Press V to hear its available moves.") % {
        from: origin_field,
        to: destination_field
      }
    end

    def parse_board_move(value)
      fields = value.to_s.split(";")
      match = /\A(\d+),(\d+)>(\d+),(\d+)\z/.match(fields.shift.to_s)
      return nil if match == nil

      metadata = fields.each_with_object({}) do |field, result|
        key, item = field.split("=", 2)
        return nil if key.to_s.empty? || item == nil
        result[key] = item
      end
      BoardMove.new(
        from: [match[1].to_i, match[2].to_i],
        to: [match[3].to_i, match[4].to_i],
        metadata: metadata
      )
    rescue TypeError
      nil
    end

    def same_board_move?(first, second)
      first != nil && second != nil && first.from == second.from && first.to == second.to &&
        first.metadata == second.metadata
    end

    def available_board_moves(_replay, _actor)
      []
    end

    protected

    def board_turn_error(replay, actor)
      return _("The game has ended. You can still inspect the board.") if replay.finished?
      return _("There is no active turn.") if replay.current_player == nil
      return nil if same_user?(replay.current_player, actor)

      _("It is %{player}'s turn.") % { player: participant_name(replay.current_player) }
    end

    def board_selection_context_error(replay, actor, field:, piece:)
      turn_error = board_turn_error(replay, actor)
      return turn_error if turn_error != nil
      return _("Field %{field} is empty.") % { field: field } if piece == nil
      if !same_user?(piece.owner, actor)
        return _("Field %{field} contains %{piece}, which belongs to your opponent.") % {
          field: field,
          piece: piece.label.to_s
        }
      end

      nil
    end
  end
end
