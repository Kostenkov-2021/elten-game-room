# Generated from tools/data/rulebooks/ludo.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class Ludo
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:route, GameRoomRules.translate("Bring all four pawns home"),
            GameRoomRules.translate("Ludo is a race for two to four players. Everyone has four pawns waiting in a base. You roll a die to bring them onto the track and move them around the board. The first player to bring all four to the finish wins."),
            GameRoomRules.translate("The shared track has 52 squares. Players enter at squares 1, 14, 27 and 40 in seating order. The numbering wraps from 52 back to 1, so everyone travels the same distance. After the shared track, each pawn enters its owner's private six-square home lane. Opponents cannot enter that lane. Its last square is the finish, and a finished pawn does not move again.")),
          rule_section(:roll, GameRoomRules.translate("A roll gives one pawn a move"),
            GameRoomRules.translate("Roll the die, then use its whole result for one pawn. You cannot split the number between pawns. When several pawns can move, choose one of the offered destinations. When only one can move, the program moves it automatically. If no pawn can move, your turn normally ends."),
            GameRoomRules.translate("Landing on an opponent's pawn sends it back to its base, unless the square is one of the four safe entry squares. Pawns on those entry squares cannot be captured. With blockades enabled, two opposing pawns sharing a track square also stop you from moving through or landing there. Your own pair does not block your other pawns; bringing a pawn out of the base is treated separately.")),
          rule_section(:options, GameRoomRules.translate("What the table options change"),
            GameRoomRules.translate("By default, a 6 or a 1 lets you bring a pawn out of the base onto its entry square, with no further movement. A 1 does not grant another roll. Turn off the option for a 1 to require a 6; turn off the restriction on leaving the base to allow any roll. These choices never force you to leave the base if another pawn can move."),
            GameRoomRules.translate("Roll again after a 6 is on by default. After resolving a six you get another roll, even if that six could not move a pawn. Turning it off makes a six end the turn like any other result."),
            GameRoomRules.translate("An exact roll is required to reach the finish is on by default. A pawn two squares from the finish needs a two: a larger result cannot move it. With this option off, an overshooting roll also takes the pawn to the finish."),
            GameRoomRules.translate("Three consecutive sixes lose the turn is on by default. The third six ends your turn without a move for that roll. Moves made after the first two sixes stay on the board: they are not undone."),
            GameRoomRules.translate("Two pawns of one player form a blockade is on by default. Turning it off removes the restrictions caused by opposing pairs on the track. It does not remove safe entry squares or change the length of the route.")),
          rule_section(:presentation, GameRoomRules.translate("Names or colours"),
            GameRoomRules.translate("Positions are read with the name or colour first, followed by the square, without pawn numbers. Ctrl+C switches names and colours throughout the game announcements and your view of game history. C always reads who has each colour. Red, blue, yellow and green follow the fixed seats at the table. Your choice is saved on this computer for future tables. It does not change other people's settings or the recorded moves. Chat and table membership messages keep the actual names.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("1: read your pawns; for an observer, read the first player's pawns."),
            GameRoomRules.translate("2: read the next player's pawns in seating order."),
            GameRoomRules.translate("3: read the next player's pawns, if present."),
            GameRoomRules.translate("4: read the last player's pawns at a four-player table."),
            GameRoomRules.translate("Arrows: choose an available pawn move."),
            GameRoomRules.translate("Enter: roll the die or confirm a pawn move."),
            GameRoomRules.translate("C: read each player's colour."),
            GameRoomRules.translate("Ctrl+C: switch between player names and colours."),
            GameRoomRules.translate("D: read who rolled last and the result, without rolling again."),
            GameRoomRules.translate("V: browse your pawns."),
            GameRoomRules.translate("Shift+V: browse everyone's pawns in track order, then home lanes, bases and finished pawns."),
            GameRoomRules.translate("P: read your unfinished pawn positions, including the base."),
            GameRoomRules.translate("Shift+P: read opponents' unfinished pawn positions, including their bases."),
            GameRoomRules.translate("S: read how many pawns each player has finished."),
            GameRoomRules.translate("T: read whose turn it is."))
        ]
      end
    end
    include GeneratedRulebook
  end
end
