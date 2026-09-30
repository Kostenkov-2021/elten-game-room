# Generated from tools/data/rulebooks/tic_tac_toe.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class TicTacToe
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:line, GameRoomRules.translate("A small board, three marks to win"),
            GameRoomRules.translate("In Tic-tac-toe, two players try to make a line of three of their own marks. The board has three rows and three columns. The first player uses X and makes the first move; the other uses O."),
            GameRoomRules.translate("On your turn, choose one empty square and place your mark there. Then it is your opponent's turn. Once placed, a mark stays where it is: you cannot move it or replace an opponent's mark."),
            GameRoomRules.translate("A line can run across a row, down a column or along either diagonal. For example, owning the top-left, centre and bottom-right squares wins the game. The game ends as soon as a line is completed, even if other squares are still empty. If the board fills up without a winning line, the result is a draw."),
            GameRoomRules.translate("Game Room uses this 3 by 3 version without additional rule variants. You may play against another person or a bot.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: browse squares."),
            GameRoomRules.translate("Enter: place your mark on the selected empty square."),
            GameRoomRules.translate("T: read whose turn it is."))
        ]
      end
    end
    include GeneratedRulebook
  end
end
