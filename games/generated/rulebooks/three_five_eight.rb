# Generated from tools/data/rulebooks/three_five_eight.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class ThreeFiveEight
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:course, GameRoomRules.translate("Eighteen deals and six contracts"),
            GameRoomRules.translate("3-5-8 is an individual game for exactly three players, using all 52 cards. Each player receives 16 cards and four cards form the kitty. The player to the dealer's left chooses the contract after seeing their first six cards, then receives the rest of their hand."),
            GameRoomRules.translate("There are six contracts: hearts, spades, diamonds and clubs as trump, no trump, and misere. During the game every player must choose each contract exactly once. The dealer moves one seat after every deal, so the complete game has 18 deals."),
            GameRoomRules.translate("After any exchanges, the chooser reveals the four-card kitty, adds it to their hand and discards four cards face down. The chooser leads the first trick. The winner of every trick leads the next one.")),
          rule_section(:play, GameRoomRules.translate("Following suit"),
            GameRoomRules.translate("Cards rank from two, the lowest, to ace, the highest. You must follow the led suit when you can, but you do not have to beat the currently winning card."),
            GameRoomRules.translate("If you cannot follow, you may play any card. You do not have to play a trump or overtrump. No-trump and misere deals have no trump suit.")),
          rule_section(:exchange, GameRoomRules.translate("Exchanging cards after the first deal"),
            GameRoomRules.translate("The table owner can disable card exchange in the game options. When it is disabled, every deal goes directly from contract selection to taking the kitty."),
            GameRoomRules.translate("Card exchange is available only in a trump contract. A player who scored above zero in the previous deal may exchange up to that many cards with players who scored below zero. A player with the higher target in the current deal exchanges first. You may stop before using the whole allowance."),
            GameRoomRules.translate("For a non-trump card, the recipient automatically returns their highest card of the same suit; if the received card is their only card of that suit, it simply returns. For a trump card, the recipient may instead return any non-trump card, or their highest trump. Exchanges are completed before the chooser takes the kitty.")),
          rule_section(:scoring, GameRoomRules.translate("Targets and scoring"),
            GameRoomRules.translate("In an ordinary deal the dealer's target is 3 tricks, the player to the dealer's right needs 5, and the chooser to the dealer's left needs 8. Your score for the deal is tricks won minus your target. The three changes therefore always total zero."),
            GameRoomRules.translate("Misere reverses the targets: the dealer may take at most 8 tricks, the player to the dealer's right at most 5, and the chooser at most 3. Your score is the limit minus tricks won, so avoiding tricks earns points and exceeding the limit loses points."),
            GameRoomRules.translate("After the eighteenth deal, the player with the highest total score wins. Equal highest totals produce a shared draw.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: browse cards or available commands."),
            GameRoomRules.translate("Enter: choose a contract, exchange or return a card, discard to the kitty, or play the selected card."),
            GameRoomRules.translate("H: read your hand."),
            GameRoomRules.translate("C: read the trick cards."),
            GameRoomRules.translate("Ctrl+C: browse the trick cards."),
            GameRoomRules.translate("F: read the current contract and trump suit."),
            GameRoomRules.translate("V: read tricks, targets and the current deal."),
            GameRoomRules.translate("S: read scores."),
            GameRoomRules.translate("T: read whose turn it is."),
            GameRoomRules.translate("Z: next legal card; play it automatically if it is the only unambiguous option."),
            GameRoomRules.translate("Shift+Z: previous legal card; play it automatically if it is the only unambiguous option."),
            GameRoomRules.translate("Shift+C: sort by suit or colour; press again to reverse the order."),
            GameRoomRules.translate("Shift+H: sort by rank or value; press again to reverse the order."),
            GameRoomRules.translate("Shift+M: restore the order in which cards were received."))
        ]
      end
    end
    include GeneratedRulebook
  end
end
