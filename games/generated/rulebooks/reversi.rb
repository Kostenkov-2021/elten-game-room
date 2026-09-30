# Generated from tools/data/rulebooks/reversi.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class Reversi
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:turning, GameRoomRules.translate("Turn your opponent's discs into your own"),
            GameRoomRules.translate("Reversi is played by two people on an 8 by 8 board. Four discs are already in the centre: two black and two white. The first player is black and starts. Unlike in many board games, captured discs stay on the board and change colour. You want more discs of your colour when the game ends, not necessarily after every move."),
            GameRoomRules.translate("Normally you place one disc on an empty square so that one or more opposing discs lie between the new disc and one of your existing discs. They must form an uninterrupted straight line. For example, placing black next to a row of white, white, black turns both white discs black."),
            GameRoomRules.translate("This works horizontally, vertically and diagonally. If your move encloses discs in several directions, all those discs turn at once. You do not choose which lines to capture. An empty square interrupts a line, and the newly turned discs do not trigger a second chain of captures elsewhere.")),
          rule_section(:options, GameRoomRules.translate("Passing and playing without a capture"),
            GameRoomRules.translate("Mandatory capture is enabled by default. With it, every placement must turn at least one opposing disc. If you switch it off, a move without a capture is also allowed, but the new disc must be next to an existing disc, including diagonally. You still cannot play on an occupied square or in an isolated part of the board. A move that does enclose opposing discs always turns them."),
            GameRoomRules.translate("Allow passing is also enabled by default. It lets you give the turn to your opponent even when you have a legal move. You may do this repeatedly; voluntary passes alone do not produce a draw. Switch the option off if you want players to pass only when they cannot place a disc."),
            GameRoomRules.translate("The game ends when the board is full or neither player has a legal placement under the selected rules. The player with more discs wins; equal numbers mean a draw. Having no move yourself does not end the game if your opponent can still play.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: browse squares."),
            GameRoomRules.translate("Enter: place a disc on the selected square."),
            GameRoomRules.translate("P: pass when the table rules allow it."),
            GameRoomRules.translate("S: read each player's number of discs."),
            GameRoomRules.translate("T: read whose turn it is."))
        ]
      end
    end
    include GeneratedRulebook
  end
end
