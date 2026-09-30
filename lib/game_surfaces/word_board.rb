require_relative "specifications"
# encoding: UTF-8
require_relative "../scrabble_rules"
require_relative "../game_session_clock"

require_relative "../game_room_localization"

module GameSurfaces
  using GameRoomLocalization::Translations


  class WordBoardGrid < OrientedGridBox
    # Scrabble labels include the coordinate between the letter and its value.
    # Keep normal grid navigation, header, markers and braille without adding
    # another coordinate before or after the complete label.
    def cell_announcement(label); label; end
  end

  class WordBoardSurface
    include ActionEmitter
    attr_accessor :program, :on_draft_changed
    def initialize(spec, state: {})
      @spec = spec
      @sort = state.fetch("sort", 0).to_i
      @order = state.fetch("order", []).select { |id| spec.rack.include?(id) }
      @order.concat(spec.rack - @order)
      @draft = state["epoch"] == spec.epoch ? state.fetch("draft", []).map(&:dup) : []
      @control = WordBoardGrid.new(15, 15, row_origin: :top, coordinate_first: true,
        header: _("Word board"), x: state.fetch("x",7), y: state.fetch("y",7), quiet: true)
      @control.on(:select) { choose_tile }
      refresh
    end
    def fields; [@control]; end
    def public_draft
      @draft.map { |tile, pos, letter| [pos, letter, @spec.tiles.fetch(tile)[:letter].empty?] }
    end
    def remote_draft=(tiles)
      return if @remote_draft == tiles
      @remote_draft = tiles
      refresh
    end
    def state
      { "x" => @control.x, "y" => @control.y, "sort" => @sort,
        "order" => @order.dup, "draft" => @draft.map(&:dup), "epoch" => @spec.epoch }
    end
    def reusable_for?(spec); spec.is_a?(WordBoardSpec); end
    def update_spec(spec)
      @draft.clear if spec.epoch != @spec.epoch || !spec.editable
      @order.select! { |tile| spec.rack.include?(tile) }
      @order.concat(spec.rack - @order)
      @spec = spec
      sort_order if @draft.empty? && @sort > 0
      refresh
      self
    end
    def suppress_next_focus!(_index = 0); @control.suppress_next_focus!; end
    def cancel_pending_action?; !@draft.empty?; end
    def save_game_error; _("Submit or cancel the draft before saving.") unless @draft.empty?; end
    def cancel_pending_action!
      return false if @draft.empty?
      @draft.clear
      refresh
      true
    end

    def handle_command(command, payload = {})
      return false unless command.to_s.start_with?("word_")
      case command.to_s.delete_prefix("word_")
      when "rack"
        labels = @order.map { |tile| rack_label(tile) }
        speak(labels.empty? ? _("Your rack is empty.") : labels.join(", "))
      when "read"
        speak(rack_label(@order[payload["slot"].to_i]))
      when "place"
        slot = payload["slot"]
        return unavailable unless slot.is_a?(Integer) && slot.between?(0, 6)
        place(@order[slot])
      when "remove", "cancel"
        if command == "word_remove"
          removed = @draft.any? { |p| p[1] == position }
          @draft.reject! { |p| p[1] == position }
        else
          @draft.clear
        end
        refresh
        @control.focus(nil, nil, true, include_header: false) if removed
      when "sort"
        return say(_("Cancel the draft before changing rack order.")) unless @draft.empty?
        @sort = (@sort + 1) % 3
        sort_order
        speak([_("Free rack order."), _("Alphabetical rack order."), _("Vowels first.")][@sort])
      when "preview", "submit"
        return unavailable unless editable?
        result = @spec.preview.call(@draft)
        return say(@spec.error_message.call(result.error)) if result.error
        if command == "word_preview"
          speak(_("%{words}: %{points} potential points.") % { words: result.words.map { |w| w[:word] }.join(", "), points: result.score })
        else
          return Action.new(kind: "word", name: "place", payload: { "placements" => @draft.map(&:dup) })
        end
      when "pass", "exchange"
        return unavailable unless editable?
        epoch = @spec.epoch
        return say(_("You can exchange tiles only when at least eight remain in the bag.")) if command == "word_exchange" && !@spec.exchange
        unless @draft.empty?
          return true unless choose(_("Cancel the draft and continue?"), [_("Yes"), _("No")]) == 0
        end
        return unavailable unless editable? && @spec.epoch == epoch
        if command == "word_pass"
          @draft.clear
          refresh
          return Action.new(kind: "word", name: "pass")
        end
        choices = @order.dup
        indices = choose(_("Choose tiles to exchange"), choices.map { |tile| rack_label(tile) }, multiple: true)
        if indices && !indices.empty? && editable? && @spec.epoch == epoch
          @draft.clear
          refresh
          return Action.new(kind: "word", name: "exchange", payload: { "tiles" => indices.map { |i| choices[i] } })
        end
      else
        return false
      end
      true
    end

    private
    def position; @control.y * 15 + @control.x; end
    def available; @order - @draft.map(&:first); end
    def editable?
      now = GameRoomSessionClock.for_state(frozen_at: @spec.frozen_at,
        clock_offset: @spec.clock_offset, clock_epoch_offset: @spec.clock_epoch_offset)
      @spec.editable && (@spec.deadline.to_i == 0 || now.to_i < @spec.deadline)
    end
    def say(text); speak(text); true; end
    def unavailable; say(_("This action is not available now.")); end
    def rack_label(tile)
      return _("Empty rack position.") unless tile && @spec.tiles[tile]
      value = @spec.tiles[tile]
      label = value[:letter].empty? ? _("blank") : value[:letter].upcase
      label = _("%{letter}, %{points} points") % { letter: label, points: value[:points] }
      label += ", " + _("in the draft") if @draft.any? { |p| p[0] == tile }
      label
    end
    def choose_tile
      return unavailable unless editable?
      choices = available
      return unavailable if choices.empty? || @spec.board[position] || @draft.any? { |p| p[1] == position }
      epoch, field = @spec.epoch, position
      index = choose(_("Choose a tile"), choices.map { |tile| rack_label(tile) })
      return if index == nil
      return unavailable unless @spec.epoch == epoch && position == field
      place(choices[index])
    end
    def place(tile, letter = nil)
      return unavailable unless editable? && available.include?(tile) && !@spec.board[position] && !@draft.any? { |p| p[1] == position }
      face = @spec.tiles[tile][:letter]
      epoch, field = @spec.epoch, position
      if face.empty? && letter == nil
        index = choose(_("Choose the blank's letter"), @spec.alphabet.map(&:upcase))
        return if index == nil
        letter = @spec.alphabet[index]
      end
      return unavailable unless editable? && @spec.epoch == epoch && position == field &&
        available.include?(tile) && !@spec.board[field] && !@draft.any? { |p| p[1] == field }
      letter ||= face
      @draft << [tile, position, letter]
      refresh
      @control.focus(nil,nil,true,include_header: false)
    end
    def sort_order
      if @sort == 0
        @order = @spec.rack.dup
      else
        @order.sort_by! do |tile|
          letter = @spec.tiles[tile][:letter]
          [(@sort == 2 && !GameRoomContent.utf8("aąeęioóuy").include?(letter) ? 1 : 0), @spec.alphabet.index(letter) || -1, tile]
        end
      end
    end
    def refresh
      public_tiles = public_draft
      if @published_draft != public_tiles
        @published_draft = public_tiles
        @on_draft_changed&.call(public_tiles)
      end
      draft = @draft.to_h { |tile,pos,letter| [pos, { letter: letter, points: @spec.tiles[tile][:points], blank: @spec.tiles[tile][:letter].empty? }] }
      draft = @remote_draft.to_a.to_h { |tile| [tile.fetch(:position), tile] } if !@spec.editable
      bonuses = { "2" => _("double letter"), "3" => _("triple letter"), "D" => _("double word"), "T" => _("triple word") }
      @control.set_cells(Array.new(15) do |y|
        Array.new(15) do |x|
          pos = y*15+x
          tile = draft[pos] || @spec.board[pos]
          if tile
            text = _("%{letter}, %{field}, %{points} points") % {
              letter: tile[:letter].upcase, field: GameRoomScrabbleRules.field(pos), points: tile[:points] }
            text += ", " + _("blank") if tile[:blank]
            text += ", " + _("draft") if draft[pos]
            text
          else
            [GameRoomScrabbleRules.field(pos), _("empty"), bonuses[GameRoomScrabbleRules.premium(pos)]].compact.join(", ")
          end
        end
      end)
    end
    def choose(prompt, labels, multiple: false)
      list = RefreshAwareListBox.new(labels, header: prompt, quiet: true, flags: multiple ? ListBox::Flags::MultiSelection : 0)
      accept, cancel = Button.new(_("Select")), Button.new(_("Cancel"))
      form = GameRoomUI::Form.new([list,accept,cancel], program: @program, quiet: true)
      form.accept_button, form.cancel_button = accept, cancel
      form.hide(accept); form.hide(cancel)
      result = nil
      accept.on(:press) { result = multiple ? list.multiselections : list.index; form.resume }
      cancel.on(:press) { form.resume }
      # A nested tile picker cannot hold the player's turn open past its clock.
      if defined?(FormTimer) && @spec.deadline.to_i > 0
        form.add_timer(FormTimer.new(0.25, repeat: true) { form.resume unless editable? })
      end
      form.wait
      EltenAPI::KeyboardState.clear_current_frame if defined?(EltenAPI::KeyboardState)
      result
    end
  end
end
