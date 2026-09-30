# Generated from tools/data/rulebooks/checkers.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class Checkers
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:diagonals, GameRoomRules.translate("Across the dark squares"),
            GameRoomRules.translate("In Checkers, two players try to leave the opponent without a piece or without a legal move. Only dark squares are used. White starts at the bottom and moves first. An ordinary piece, called a man, normally moves one empty square diagonally towards the far side of the board."),
            GameRoomRules.translate("To capture, jump over an opposing piece onto an empty square beyond it. A man needs the opponent to be on the adjacent diagonal square. Reaching the farthest row gives you a king, which can move and capture in both directions. The settings below decide how far a king can travel and whether men may go backwards."),
            GameRoomRules.translate("The board size may be 8 by 8, 10 by 10 or 12 by 12. These sizes give each side 12, 20 or 30 pieces respectively. Two rows in the middle begin empty. Changing the size does not automatically change the movement or capture rules, so check the other settings as well.")),
          rule_section(:captures, GameRoomRules.translate("One jump, or a whole capture sequence?"),
            GameRoomRules.translate("With mandatory capture enabled, an available capture takes priority over every ordinary move, even if it is a different piece that can capture. This is enabled by default. Turning it off lets you choose a non-capturing move instead."),
            GameRoomRules.translate("Completing a capture sequence is also enabled by default. After the first jump, keep using the same piece while it can capture again. You choose each landing square separately. If this setting is disabled, the turn ends after a single jump."),
            GameRoomRules.translate("Maximum capture, enabled by default, makes you choose a complete route that captures as many pieces as possible. Suppose one of your men can take one piece, while another can take three by successive jumps: you must choose the three-piece route. This rule requires both mandatory capture and completing the sequence. An optional further rule gives a king priority over a man when both have equally long maximum routes; that priority is off by default."),
            GameRoomRules.translate("Captured pieces normally remain as obstacles until the whole sequence ends. You cannot jump over the same captured piece again. If you disable delayed removal, each victim disappears immediately, which can open a route that would otherwise be blocked.")),
          rule_section(:movement, GameRoomRules.translate("Choose how men and kings move"),
            GameRoomRules.translate("Men may capture backward is on by default. It allows backward jumps but does not allow ordinary backward moves. Those are controlled by the separate Men may move backward without capturing setting, which is off by default."),
            GameRoomRules.translate("Kings move and capture over any distance is on by default. Such a king travels along a clear diagonal and may land on an empty square beyond the opposing piece it jumps. It cannot jump two occupied squares in a single jump. If the setting is off, a king moves one square or makes a short capture jump, still in either direction."),
            GameRoomRules.translate("Promotion normally happens at the end of a move. Promote immediately during a capture sequence changes this: a man reaching the last row during a jump becomes a king straight away and continues using king movement. This option is off by default.")),
          rule_section(:result, GameRoomRules.translate("Winning, draws and square names"),
            GameRoomRules.translate("You win if your opponent has no pieces left or no legal move. The program declares a draw when a position occurs three times, or after 80 individual moves without a capture or promotion."),
            GameRoomRules.translate("The board can use numbered dark squares or chess-style coordinates. Numbered boards have 32, 50 or 72 playable squares, depending on size. Switching notation or rotating the view changes only how you inspect the board, not the rules or the other player's view.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: browse squares."),
            GameRoomRules.translate("Enter: select a piece and its destination; choose each jump separately."),
            GameRoomRules.translate("V: read possible moves."),
            GameRoomRules.translate("K: browse your draughts kings."),
            GameRoomRules.translate("Shift+K: browse the opponent's draughts kings."),
            GameRoomRules.translate("C: read player colours."),
            GameRoomRules.translate("S: read remaining men and kings."),
            GameRoomRules.translate("Ctrl+H: switch numbered and chess notation."),
            GameRoomRules.translate("Ctrl+Shift+H: rotate the board view."),
            GameRoomRules.translate("T: read whose turn it is."))
        ]
      end
    end
    include GeneratedRulebook
  end
end
