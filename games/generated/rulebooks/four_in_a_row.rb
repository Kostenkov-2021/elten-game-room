# Generated from tools/data/rulebooks/four_in_a_row.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class FourInARow
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:falling, GameRoomRules.translate("Build a line from falling pieces"),
            GameRoomRules.translate("Two players take turns dropping pieces into a board with seven columns and six rows. Your aim is to join at least four of your own pieces in a straight line. The first player at the table starts."),
            GameRoomRules.translate("Each turn consists of choosing one column. Your piece falls to the lowest empty square in that column. You cannot leave it suspended higher up: if the column is empty, it lands at the bottom; if it already holds two pieces, yours rests on top of them. A full column cannot accept another piece."),
            GameRoomRules.translate("A winning line may be horizontal, vertical or diagonal. All its pieces must touch: a gap or an opponent's piece breaks the line. Completing a line ends the game immediately. If all 42 squares fill up without a winner, the game is drawn."),
            GameRoomRules.translate("There are no optional board sizes or alternative placement rules in this game. Either player can be a bot.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: browse the board."),
            GameRoomRules.translate("Enter: drop a piece into the selected column."),
            GameRoomRules.translate("T: read whose turn it is."))
        ]
      end
    end
    include GeneratedRulebook
  end
end
