# Generated from tools/data/rulebooks/scrabble.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class Scrabble
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:crossword, GameRoomRules.translate("Build one crossword together"),
            GameRoomRules.translate("Two to four people play on a 15-by-15 board, using letter tiles to score words. There are no bots in this game. Everyone starts with seven tiles on a private rack and refills towards seven after playing, while tiles remain in the bag. The first word must cross the centre, H8. Later moves must connect to the existing crossword."),
            GameRoomRules.translate("In one move, place your new letters in a single row or column. Existing letters may fill the spaces between them, but the completed line cannot have empty gaps. Words read left to right or top to bottom, never diagonally. You may extend a word, cross it, or place letters beside it to make several shorter words. Every newly created word must be valid, not just the longest one. Accepted letters stay in place for the rest of the game.")),
          rule_section(:draft, GameRoomRules.translate("Watch a word being built"),
            GameRoomRules.translate("Other players and observers can see the letters you place before you submit your word. Moving or removing a draft tile updates their boards without moving their cursors. Only letters already placed on the board are shared, not the rest of your rack. This is a preview: points and the permanent board change only after the move is accepted. Passing, a timeout or the end of the game removes the unfinished draft.")),
          rule_section(:dictionary, GameRoomRules.translate("The chosen language decides which words count"),
            GameRoomRules.translate("Choose Polish or English for the tiles and dictionary, independently of your interface language. Polish uses the SJP data dated 2026-09-01; English uses Wordnik data dated 2021-07-29. These are the local word lists supplied with Power Games, not the official OSPS, NWL, Collins or QC lists. Words contain two to fifteen letters and are checked against the selected list when you submit the move."),
            GameRoomRules.translate("Each language has 100 tiles, including two blanks, but different letter quantities and values. A blank can represent a letter you choose when placing it. It always scores zero and keeps that chosen letter after the move is accepted. It cannot later be changed into another letter or recovered from the board.")),
          rule_section(:points, GameRoomRules.translate("How a move earns points"),
            GameRoomRules.translate("For each new word, add the values of all its letters, including letters already on the board. A newly covered letter bonus doubles or triples that tile's value. After letter bonuses, apply the word bonuses to the whole word. Several word multipliers multiply together. For example, two double-word fields make the word worth four times its letter total."),
            GameRoomRules.translate("A letter shared by two new words scores in both. Bonuses work only on the move that first covers them; extending a word later does not activate its old bonuses again. A blank still scores zero on a letter bonus, but can activate a word bonus. Using all seven rack tiles in one move adds 50 points after the word totals have been calculated.")),
          rule_section(:alternatives, GameRoomRules.translate("You may exchange or pass instead"),
            GameRoomRules.translate("Exchange one to seven tiles only when at least eight are left in the bag. Select the tiles to return and confirm the exchange; this uses your turn. In this version, returned tiles go back into the bag before it is shuffled and replacements are drawn, so you may get a returned tile again. You can also pass without exchanging. Neither choice places an unfinished draft on the board.")),
          rule_section(:invalid, GameRoomRules.translate("What happens to an unrecognised word"),
            GameRoomRules.translate("Invalid word offers six policies. Choose whether an invalid submission lets you correct the move or ends your turn, and whether it costs zero, 5 or 10 points. The default is correction without a penalty. One submitted attempt incurs at most one penalty, even if several words are invalid. The draft returns to the rack and does not use any board bonuses."),
            GameRoomRules.translate("Placement errors, such as a disconnected word or a gap, are not penalised as invalid words. Y previews the words and their points but deliberately does not consult the dictionary. A preview is therefore not a guarantee that a word will be accepted. Dictionary checking happens only when you submit.")),
          rule_section(:ending, GameRoomRules.translate("The last tiles and the final score"),
            GameRoomRules.translate("Thinking time is zero for no limit, or 20\u2013600 seconds per turn. Choosing a blank and correcting a word use the same turn time. Timeout cancels the unsubmitted draft and passes; it does not draw tiles or charge a separate point penalty."),
            GameRoomRules.translate("The game ends when someone empties their rack and the bag is empty. It also ends as blocked when exchanging is unavailable and three complete circuits pass without a tile being placed. A legal word worth zero still breaks this sequence. At the end, subtract each player's remaining tile values. If a player went out, they also gain the other players' remaining values; a blocked game has no such bonus. Blanks are worth zero. The highest adjusted score wins, with a shared result if tied.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: move around the board."),
            GameRoomRules.translate("Enter: on an empty square, choose a rack tile, then place it; a blank asks for its letter."),
            GameRoomRules.translate("Backspace: remove your unsubmitted tile under the cursor."),
            GameRoomRules.translate("Z: clear the whole draft."),
            GameRoomRules.translate("F: submit the draft."),
            GameRoomRules.translate("Escape: cancel the current tile or exchange choice."),
            GameRoomRules.translate("C: read the rack."),
            GameRoomRules.translate("I: cycle receipt, alphabetic and vowel-first order after clearing the draft."),
            GameRoomRules.translate("Y: preview the words and their points."),
            GameRoomRules.translate("L: browse played words."),
            GameRoomRules.translate("G: choose tiles to exchange; Space selects and Enter confirms in that list."),
            GameRoomRules.translate("P: pass your turn."),
            GameRoomRules.translate("E: read tile counts."),
            GameRoomRules.translate("S: read scores."),
            GameRoomRules.translate("T: read whose turn it is."),
            GameRoomRules.translate("1: read rack position 1, without placing it."),
            GameRoomRules.translate("2: read rack position 2, without placing it."),
            GameRoomRules.translate("3: read rack position 3, without placing it."),
            GameRoomRules.translate("4: read rack position 4, without placing it."),
            GameRoomRules.translate("5: read rack position 5, without placing it."),
            GameRoomRules.translate("6: read rack position 6, without placing it."),
            GameRoomRules.translate("7: read rack position 7, without placing it."),
            GameRoomRules.translate("Shift+1: place rack tile 1 on the current square; a blank asks for its letter."),
            GameRoomRules.translate("Shift+2: place rack tile 2 on the current square; a blank asks for its letter."),
            GameRoomRules.translate("Shift+3: place rack tile 3 on the current square; a blank asks for its letter."),
            GameRoomRules.translate("Shift+4: place rack tile 4 on the current square; a blank asks for its letter."),
            GameRoomRules.translate("Shift+5: place rack tile 5 on the current square; a blank asks for its letter."),
            GameRoomRules.translate("Shift+6: place rack tile 6 on the current square; a blank asks for its letter."),
            GameRoomRules.translate("Shift+7: place rack tile 7 on the current square; a blank asks for its letter."))
        ]
      end
    end
    include GeneratedRulebook
  end
end
