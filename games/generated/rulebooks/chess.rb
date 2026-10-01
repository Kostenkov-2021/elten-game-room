# Generated from tools/data/rulebooks/chess.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class Chess
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:king, GameRoomRules.translate("The king is what you are protecting"),
            GameRoomRules.translate("Chess is a game for two players. White moves first, then the players alternate one move at a time. Each begins with a king, queen, two rooks, two bishops, two knights and eight pawns on an 8 by 8 board. Your aim is to attack the opposing king in a way your opponent cannot escape: this is checkmate. You do not actually capture the king."),
            GameRoomRules.translate("You capture an opposing piece by moving one of yours onto its square. You cannot land on a piece of your own colour. Nor may you make a move that exposes your king to attack, even if the move would otherwise be possible.")),
          rule_section(:pieces, GameRoomRules.translate("Getting to know the pieces"),
            GameRoomRules.translate("The rook moves any distance along a row or column. The bishop moves any distance diagonally. The queen combines both movements. None of these pieces can jump over another piece. For example, a rook blocked by your own pawn must wait for the pawn to move or choose another direction."),
            GameRoomRules.translate("The knight moves in an L: two squares along a row or column, then one square sideways. It can jump over pieces in between. The king normally moves one square in any direction, but never onto a square attacked by the opponent. Two kings therefore cannot stand next to each other."),
            GameRoomRules.translate("A pawn moves forward towards the opponent's starting side. It advances one square into an empty square. From its starting row it may instead advance two, provided both squares are empty. It captures differently: one square diagonally forward. A pawn cannot move backwards or capture straight ahead."),
            GameRoomRules.translate("A pawn reaching the farthest row is promoted. Choose a queen, rook, bishop or knight from the list. This choice is not limited to pieces that have already been captured: you can have two queens.")),
          rule_section(:special, GameRoomRules.translate("Two special moves"),
            GameRoomRules.translate("Castling moves the king and a rook in one turn. Move your king two squares towards the chosen rook; the program moves the rook to the square the king crossed. Both pieces must still have their original castling rights, and the squares between them must be empty. You cannot castle out of check, through an attacked square or into check. Both kingside and queenside castling are supported."),
            GameRoomRules.translate("En passant is a special pawn capture. If an opposing pawn advances two squares and finishes beside your pawn, you may capture it as though it had advanced only one. Move diagonally to the square it passed through. This opportunity exists only on your very next move; if you play something else, it is gone.")),
          rule_section(:mate, GameRoomRules.translate("Check, mate and the end of the game"),
            GameRoomRules.translate("Check means that your king is under attack. You must answer it by moving the king, capturing the attacker or blocking the attack, whichever is legal. If no legal reply exists, it is checkmate and you lose. If you have no legal move but your king is not attacked, it is stalemate and the game is drawn."),
            GameRoomRules.translate("Power Games also ends the game automatically on threefold repetition, after 50 moves by each side without a pawn move or capture, and in the insufficient-material positions recognised by the program. You do not have to claim these draws. There is no chess clock or alternative chess variant in the current game.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: browse squares."),
            GameRoomRules.translate("Enter: select your piece, then its destination; choose a promotion if needed."),
            GameRoomRules.translate("V: read legal destinations for the inspected piece."),
            GameRoomRules.translate("E: read pieces attacking the inspected square."),
            GameRoomRules.translate("C: read player colours."),
            GameRoomRules.translate("S: read each player's remaining pieces."),
            GameRoomRules.translate("Ctrl+Shift+H: rotate the board view."),
            GameRoomRules.translate("T: read whose turn it is."),
            GameRoomRules.translate("K: browse your kings."),
            GameRoomRules.translate("Shift+K: browse the opponent's kings."),
            GameRoomRules.translate("D: browse your queens."),
            GameRoomRules.translate("Shift+D: browse the opponent's queens."),
            GameRoomRules.translate("R: browse your rooks."),
            GameRoomRules.translate("Shift+R: browse the opponent's rooks."),
            GameRoomRules.translate("B: browse your bishops."),
            GameRoomRules.translate("Shift+B: browse the opponent's bishops."),
            GameRoomRules.translate("N: browse your knights."),
            GameRoomRules.translate("Shift+N: browse the opponent's knights."),
            GameRoomRules.translate("P: browse your pawns."),
            GameRoomRules.translate("Shift+P: browse the opponent's pawns."))
        ]
      end
    end
    include GeneratedRulebook
  end
end
