require_relative 'game_room_localization'

module GameRoomColourBoardPresentation
  using GameRoomLocalization::Translations
  private

  def colour_assignments(replay)
    _("White: %{white}. Black: %{black}.") % {
      white: participant_name(replay.players[0]), black: participant_name(replay.players[1])
    }
  end

  def board_orientation(replay, viewer)
    index = player_index(replay.players, viewer)
    if index == nil
      return { default: 'normal', labels: {
        'normal' => _("The first player's pieces are at the bottom."),
        'rotated' => _("The second player's pieces are at the bottom.")
      } }
    end
    own = index == 0 ? 'normal' : 'rotated'
    other = own == 'normal' ? 'rotated' : 'normal'
    { default: own, labels: {
      own => _("Your pieces are at the bottom."), other => _("The opponent's pieces are at the bottom.")
    } }
  end
end
