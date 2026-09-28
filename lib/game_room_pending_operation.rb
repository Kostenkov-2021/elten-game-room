require_relative "game_room_localization"

module GameRoomUI
  # Only controls owned by the still displayed table receive this gate. Cursor
  # movement and editing remain native; activation must not prepare a second
  # move before the first request has an authoritative outcome.
  module ActivationGate
    attr_accessor :game_room_activation_guard

    def trigger(event, *arguments)
      if [:select, :press].include?(event) && game_room_activation_guard
        return unless game_room_activation_guard.call
      end
      super
    end
  end

  class PendingOperation
    using GameRoomLocalization::Translations
    attr_reader :form, :table_id, :session_id, :view_generation, :input_mode

    LOCAL_COMMANDS = %w[
      sort_cards navigate_playable_card navigate_playable_tile announce_packet
      toggle_orientation toggle_coordinate_labels toggle_player_labels
      announce_moves navigate_piece announce_square_details announce_dice
      show_categories word_rack word_read word_sort word_preview meld_read
      scores server position echo crowd perspective_first perspective_second
      perspective_third perspective_fourth
      tile_table tile_side meld_table open_menu
    ].freeze

    def initialize(layout:, table_id:, session_id:, token:, title:, clock: nil)
      @layout, @form = layout, layout.form
      raise ArgumentError, "a table operation is already pending" if @form.game_room_pending_operation
      @table_id, @session_id, @token, @title = table_id, session_id, token, title
      @view_generation = layout.binding_generation
      @input_mode = :navigation
      @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      @started_at = @clock.call
      @previous_background_help = @form.game_room_background_help_enabled
      @form.game_room_background_help_enabled = true
      @form.game_room_pending_operation = self
      @guard = method(:reject_action)
      @controls = @form.fields.dup
      @controls.each { |field| field.extend(ActivationGate) unless field.is_a?(ActivationGate) }
      @previous_guards = @controls.map(&:game_room_activation_guard)
      @controls.each { |field| field.game_room_activation_guard = @guard }
      @surface = layout.surface
      @surface.action_guard = @guard if @surface.respond_to?(:action_guard=)
    end

    def active?
      !@closed && @form.game_room_pending_operation.equal?(self) &&
        @layout.binding_generation == @view_generation && @layout.session_id == @session_id
    end

    def safe_shortcut?(shortcut)
      [:announcement, :browse].include?(shortcut.kind) ||
        (shortcut.kind == :surface && LOCAL_COMMANDS.include?(shortcut.action_name.to_s))
    end

    def reject_action
      now = @clock.call
      if active? && (!@last_notice || now - @last_notice >= 2.0)
        @last_notice = now
        @form.__send__(:speak, GameRoomContent.utf8(_("Please wait...")))
      end
      false
    end

    def update
      unless active?
        @token.cancel(EltenAPI::Tasks::Cancelled.new("Table view changed"))
        return
      end
      if !@form.game_room_background_help? && @form.__send__(:key_pressed?, :key_escape)
        @token.cancel(EltenAPI::Tasks::Cancelled.new("Task cancelled"))
        @form.__send__(:clear_game_room_key)
        return
      end
      if !@announced && @clock.call - @started_at >= 5.0
        @announced = true
        reject_action
      end
      @form.update
    end

    def close
      return if @closed
      @closed = true
      @controls.each_with_index do |field, index|
        field.game_room_activation_guard = @previous_guards[index] if field.game_room_activation_guard.equal?(@guard)
      end
      @surface.action_guard = nil if @surface.respond_to?(:action_guard=)
      @form.game_room_pending_operation = nil if @form.game_room_pending_operation.equal?(self)
      @form.game_room_background_help_enabled = @previous_background_help
    end
  end

  # Identity and edit generation, not text equality alone: deleting a sent
  # draft and typing the same words again creates a different draft.
  ChatSubmission = Struct.new(:control, :generation, :session_id, :text, keyword_init: true) do
    def self.capture(control, session_id:)
      new(control: control, generation: control.game_room_edit_generation,
        session_id: session_id, text: control.text.to_s.dup.freeze).freeze
    end

    def clear_if_current(current_control, session_id:)
      return false unless current_control.equal?(control) && self.session_id == session_id &&
        generation == control.game_room_edit_generation
      control.set_text("")
      control.index = control.check = 0
      true
    end
  end
end
