require_relative 'game_content'

module GameRoomHistory
  # Native index/check are character positions, never event numbers. Keep the
  # event offsets separately so multiline entries can be navigated as a whole.
  class View < GameSurfaces::RefreshAwareEditBox
    attr_reader :items

    def initialize(header: '')
      super(GameRoomContent.utf8(header), type: EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine, text: '', quiet: true)
      @items, @offsets = [], []
    end

    def entry_index
      @offsets.rindex { |offset| offset <= index.to_i } || 0
    end

    def entry_index=(value)
      offset = @offsets[value.to_i.clamp(0, [@offsets.length - 1, 0].max)] || 0
      restore_selection(index: offset, check: offset)
    end

    def following_tail?
      index.to_i == check.to_i && (@items.empty? || entry_index == @items.length - 1)
    end

    def focus(index = nil, count = nil, spk = true)
      previous_focus = @history_focus
      @history_focus = true
      super
    ensure
      @history_focus = previous_focus
    end

    def read_text(index = 0, head = '')
      # Native focus calls read_text(0), which reads the whole field and moves
      # the caret through its speech callbacks. Keep the native role, marker
      # and Braille presentation, but announce only this entry on focus.
      # Explicit Read all commands outside focus retain the native behaviour.
      return super unless @history_focus

      message = [GameRoomContent.utf8(head), @items[entry_index].to_s].reject(&:empty?).join("\n")
      speak(message) unless message.empty?
    end

    def restore_selection(index:, check:)
      # Native EditBox#text exports CRLF, but its caret counts internal LF.
      maximum = text_len
      self.index = index.to_i.clamp(0, maximum)
      self.check = check.to_i.clamp(0, maximum)
    end

    def replace_entries(items, follow_tail: following_tail?)
      # Compare values, not array identity: callers may edit an earlier entry
      # in place. Already normalized text needs no allocation on a warm view.
      incoming = items.to_a
      return if @items == incoming
      values = incoming.map { |item| GameRoomContent.utf8(item).delete("\r").sub(/\n+\z/, '') }
      return if @items == values
      previous_index, previous_check = index.to_i, check.to_i
      anchors = [previous_index, previous_check].map do |position|
        row = @offsets.rindex { |offset| offset <= position }
        next unless row
        [@items[row], @items[0...row].count(@items[row]), position - @offsets[row]]
      end
      @items = values
      offset = 0
      @offsets = values.map do |value|
        start = offset
        offset += value.length + 1
        start
      end
      set_text(values.join("\n"), false)
      if follow_tail
        self.entry_index = values.length - 1
      else
        positions = anchors.each_with_index.map do |anchor, i|
          row = anchor && @items.each_index.select { |n| @items[n] == anchor[0] }[anchor[1]]
          row ? @offsets[row] + [anchor[2], @items[row].length].min : [previous_index, previous_check][i]
        end
        restore_selection(index: positions[0], check: positions[1])
      end
    end
  end
end
