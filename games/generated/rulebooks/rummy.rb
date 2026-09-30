# Generated from tools/data/rulebooks/rummy.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class Rummy
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:table, GameRoomRules.translate("Turn a hand of cards into combinations"),
            GameRoomRules.translate("Rummy is a game for two to eight players. Each receives fourteen cards. Two decks are used for two to four players, three for five or six, and four for seven or eight; every deck includes two jokers. The Identities option always uses four decks. Your main task is to place cards in valid combinations and eventually empty your hand."),
            GameRoomRules.translate("Normally you begin your turn by drawing, then may make several combinations, add cards to combinations already on the table or carry out permitted manipulations. Discarding one card ends the turn. In No discard mode, finish without discarding. You cannot work on the table before drawing, except when no source of cards remains. Emptying your hand ends the round immediately: you do not need to keep an extra card just to discard it.")),
          rule_section(:combinations, GameRoomRules.translate("Runs, sets and the position of a joker"),
            GameRoomRules.translate("A run contains at least three consecutive cards of the same suit, placed in ascending order. For example, 6, 7 and 8 of hearts is a run; three sevens of different suits are not. An ace may come before 2 or after king, so A-2-3 and Q-K-A are valid, but K-A-2 is not. A set contains three or four cards of the same rank in different suits."),
            GameRoomRules.translate("Each combination may contain at most one joker and must have at least two natural cards. A joker fills the missing position, but is still read aloud as joker so you can locate it. Selection order matters: joker, 3, 4 of spades means a low run, whereas 3, 4 of spades, joker ends with a five. The game does not rearrange a selected packet to guess what you intended."),
            GameRoomRules.translate("Identities, off by default, also permits three or four identical cards: the same rank and suit from different decks. This is different from an ordinary set, whose suits must differ. An identity combination gains an extra 10 points per card when scoring melds; the elimination mode still does not award points for melds.")),
          rule_section(:opening, GameRoomRules.translate("Your first meld opens access to the table"),
            GameRoomRules.translate("At the start of each round, everyone must make their own first meld. Its minimum value defaults to 30 points and can be set from 15 to 90. You may prepare several new combinations from your own hand and submit them together to reach that value. A single combination below the threshold is not enough just because you hope to add another later."),
            GameRoomRules.translate("Until that first meld is accepted, you cannot draw from the discard pile, add to existing combinations, recover jokers or take and merge combinations. Once you have opened, you may use other players' combinations as well as your own. This permission resets with the next round.")),
          rule_section(:discard, GameRoomRules.translate("Choose how the discard pile works"),
            GameRoomRules.translate("No discard mode removes discarding and drawing from discards. Discard only lets players discard at the end of a turn, but nobody may take those cards. Single discard, the default, lets an eligible player draw the top discarded card instead of drawing from the stock. Only that top card is available to inspect in this mode."),
            GameRoomRules.translate("Multiple discard shows the pile with the newest card first. Choosing a card also takes every newer card above it: the third item takes the third, second and first cards. You may retain discarded cards in your hand; drawing one does not require immediate use. When the stock runs out, older discards can be shuffled into it while the top discard remains on the table.")),
          rule_section(:joker, GameRoomRules.translate("Recover a joker by replacing it"),
            GameRoomRules.translate("A joker in your hand cannot be added directly to an existing combination. Use it when making a new combination with at least two natural cards. With manipulations enabled, those cards may include ones you have legally taken from the table. This restriction also matters after recovering a joker: having somewhere to put a normal card does not necessarily give you somewhere to put the joker."),
            GameRoomRules.translate("After your first meld, you can recover a table joker by playing the natural card needed in its place. This is a use of the replacement card, not a separate command on the joker. In a three-card set with two natural suits and a joker, first add a third natural suit; the remaining fourth suit can then replace the joker. You cannot simply pull out a joker and leave an invalid combination behind."),
            GameRoomRules.translate("A recovered joker is a borrowed table card. Play it back onto the table before ending your turn to avoid a 300-point penalty. You may keep it instead and accept that penalty. The same rule applies to other borrowed cards in the manipulation variant. Discarding a borrowed card does not count as playing it back.")),
          rule_section(:manipulation, GameRoomRules.translate("Taking and merging table combinations"),
            GameRoomRules.translate("Combination manipulations is off by default. With it enabled, and after drawing and completing your first meld, you may take a whole combination without a joker, remove an end card from a run or a card from a set if what remains is still valid, and merge compatible combinations. The remaining combination must still contain at least three cards; existing joker assignments cannot silently change. To take a whole combination containing a joker, recover the joker first."),
            GameRoomRules.translate("You need not return every borrowed card, but each one left unplayed at the end of the turn costs 300 points. Two retained cards therefore cost 600. This is charged once; on later turns those cards are ordinary hand cards. An equivalent copy can repay one borrowed card, not several. In normal scoring, taking a card also removes its previous meld value; putting it back awards its new meld value. Moving cards around is not a source of free repeated points.")),
          rule_section(:values, GameRoomRules.translate("Card values and rounding"),
            GameRoomRules.translate("Rounding scores to units of five is on by default. With it, cards 2\u20139 are worth 5, and 10, jack, queen and king are worth 10. An ace before 2 is worth 5; a high ace or an ace in a set is worth 15. Without rounding, 2\u20139 use their printed values, face cards and 10 are worth 10, a low ace is worth 1 and a high or set ace 11. An ace left in your hand uses the high value."),
            GameRoomRules.translate("A played joker scores as the card it represents; a joker left in the hand is worth 20. For example, with rounding, a run of 3, 4 and joker scores 15 because it represents 3-4-5. The same card values are used when checking your first meld and counting unfinished hands.")),
          rule_section(:normal, GameRoomRules.translate("Normal scoring rewards what you lay down"),
            GameRoomRules.translate("In either scoring mode, the score limit can be any whole number from 1 to 100000. Changing it alters when the match ends, not the values of cards or penalties."),
            GameRoomRules.translate("In normal mode, earn points for your melded and laid-off cards. The player who empties their hand also receives the value of the cards remaining in the other hands. Finishing in the same turn as your first meld is a rummy: it adds 200 points, or 300 instead if you use only your own hand without laying off or borrowing from the table. Doing this before anyone else has made a first meld adds another 100."),
            GameRoomRules.translate("Penalties subtract from your score. The score limit defaults to 1000 and is checked after the round, not as soon as a meld crosses it. The highest score wins; a tied lead requires further play. If the round becomes blocked, everyone keeps the points they earned, but nobody receives the finishing bonus or the others' hand values.")),
          rule_section(:elimination, GameRoomRules.translate("Elimination reverses the aim"),
            GameRoomRules.translate("Elimination mode is an optional checkbox. Here, fewer points are better. Melds and laid-off cards earn nothing; at the end of a round everyone counts the cards still in their hand, so the finisher receives zero for cards. A rummy doubles opponents' hand values. A rummy made solely from your own hand triples them, or quadruples them if nobody else had opened. Separate penalties are not multiplied."),
            GameRoomRules.translate("The elimination limit defaults to 500. Check it after settling the whole round: reaching or exceeding it eliminates a player. If everyone would go out together, the lowest total wins, with a shared result for equal lowest scores. Normally the last player below the limit wins. A blocked round simply charges each remaining hand, without a rummy multiplier. Penalties, including 300 for an unreturned table card, add points in this mode rather than subtracting them.")),
          rule_section(:time, GameRoomRules.translate("Time limits and a blocked round"),
            GameRoomRules.translate("Thinking time is zero for unlimited play, or 20\u2013600 seconds for the entire turn. Menus and preparing combinations use that time too. On timeout you lose 50 points in normal mode or gain 50 in elimination. If you have not drawn yet, the game draws one stock card when available; it does not draw another if you already drew. Your turn then ends without a discard. Penalties for borrowed cards still apply as well."),
            GameRoomRules.translate("Two full circuits without drawing or placing an original hand card block the round. Taking cards from the table and returning them alone does not keep a round alive indefinitely. A saved game must be taken at a clean turn boundary, before drawing or manipulating combinations.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: browse cards or combinations."),
            GameRoomRules.translate("Enter: in a draft, add the card in order; otherwise choose a matching meld or discard."),
            GameRoomRules.translate("Delete: discard the current card immediately."),
            GameRoomRules.translate("Space: draw from the stock."),
            GameRoomRules.translate("D: read visible discards without opening a list."),
            GameRoomRules.translate("Shift+D: take the sole available discard, or open the discard list."),
            GameRoomRules.translate("N: start a new combination in the draft."),
            GameRoomRules.translate("F: submit the prepared combinations."),
            GameRoomRules.translate("Shift+F: finish the turn without discarding in No discard mode."),
            GameRoomRules.translate("P: read the draft."),
            GameRoomRules.translate("Shift+P: edit the draft."),
            GameRoomRules.translate("Escape: cancel the current choice or draft."),
            GameRoomRules.translate("C: browse table combinations; their context menu contains available taking and merging actions."),
            GameRoomRules.translate("E: read card counts."),
            GameRoomRules.translate("Z: next card with a legal immediate lay-off; only a sole unambiguous addition may be automatic."),
            GameRoomRules.translate("Shift+Z: previous card with a legal immediate lay-off; only a sole unambiguous addition may be automatic."),
            GameRoomRules.translate("S: read scores."),
            GameRoomRules.translate("T: read whose turn it is."),
            GameRoomRules.translate("Shift+C: sort by suit or colour; press again to reverse the order."),
            GameRoomRules.translate("Shift+H: sort by rank or value; press again to reverse the order."),
            GameRoomRules.translate("Shift+M: restore the order in which cards were received."))
        ]
      end
    end
    include GeneratedRulebook
  end
end
