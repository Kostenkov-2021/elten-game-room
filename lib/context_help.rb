require_relative "game_content"

module GameRoomContextHelp
  module DynamicTips
    attr_writer :game_room_context_help_tips
    attr_accessor :game_room_context_help_provider
    attr_accessor :game_room_game_help_tips
    attr_accessor :game_room_non_game_help_tips

    def game_room_context_help_tips
      game_room_context_help_provider ? game_room_context_help_provider.call : @game_room_context_help_tips
    end

    def get_tips
      inherited = defined?(super) ? super.to_a : []
      (game_room_game_help_tips.to_a + game_room_context_help_tips.to_a + inherited).uniq
    end
  end

  module_function

  def shortcut_tip(key, action)
    label = GameRoomContent.utf8(action).strip.sub(/\.+\z/, "")
    "#{GameRoomContent.utf8(key)}, #{label}."
  end

  # F1 and the rules' in-game list read the same bound definitions. Removing
  # room actions does not remove a game action whose text happens to match one.
  def field_tips(field, include_context: true)
    game = field.respond_to?(:game_room_game_help_tips) ? field.game_room_game_help_tips.to_a : []
    context = field.respond_to?(:game_room_context_help_tips) ? field.game_room_context_help_tips.to_a : []
    inherited = field.respond_to?(:get_tips) ? field.get_tips.to_a : []
    game, context, inherited = [game, context, inherited].map { |items| clean_tips(items) }
    if !include_context && field.respond_to?(:game_room_non_game_help_tips)
      inherited -= clean_tips(field.game_room_non_game_help_tips)
    end
    (game + (include_context ? context : []) + (inherited - game - context)).uniq
  end

  def game_field_tips(fields)
    fields.to_a.flat_map { |field| field_tips(field, include_context: false) }.uniq
  end

  def clean_tips(tips)
    tips.to_a.map { |tip| GameRoomContent.utf8(tip).strip }.reject(&:empty?).uniq
  end

  def exclude_from_game_help(fields, tips)
    fields.to_a.each do |field|
      field.extend(DynamicTips) if !field.singleton_class.ancestors.include?(DynamicTips)
      field.game_room_non_game_help_tips = clean_tips(field.game_room_non_game_help_tips.to_a + tips)
    end
  end

  # Context actions change with the current screen and game phase. Keep their
  # help separate from a control's permanent tips so obsolete shortcuts can be
  # replaced instead of accumulating for the lifetime of the shared form.
  def replace(fields, tips, source: :context)
    current = clean_tips(tips)
    fields.to_a.each do |field|
      next if !field.respond_to?(:add_tip)

      field.extend(DynamicTips) if !field.singleton_class.ancestors.include?(DynamicTips)
      if source == :game
        field.game_room_game_help_tips = current
      else
        field.game_room_context_help_provider = nil
        field.game_room_context_help_tips = current
      end
    end
  end
end
