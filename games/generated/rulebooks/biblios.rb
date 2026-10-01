# Generated from tools/data/rulebooks/biblios.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class Biblios
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:library, GameRoomRules.translate("Build a library in five categories"),
            GameRoomRules.translate("In Biblios, two to four players compete to build the most valuable monastery library. Collect cards in five categories: Pigments, Monks, Forbidden Tomes, Holy Books and Manuscripts. Cards have values and letters. The total value in a category determines who wins that category, but the die on the Scriptorium determines how many victory points it is worth. Each die starts at 3 and can later range from 1 to 6."),
            GameRoomRules.translate("For example, you might collect 12 points of Monks and beat an opponent's 10. If the Monk die shows 4 at the end, you receive 4 victory points, not 12. Gold cards pay for purchases, while Church cards change the dice. The game has two distinct halves: first the free distribution of gifts, then auctions."),
            GameRoomRules.translate("Power Games uses 87 cards: 45 category cards, 18 Gold cards and 24 Church cards. Before play, the game removes two Gold cards of each value and 21 random cards for two players, one Gold card of each value and 12 random cards for three, or seven random cards for four. You do not know the random removals, so not every card is guaranteed to appear.")),
          rule_section(:gifts, GameRoomRules.translate("Decide where each gift goes before seeing the next"),
            GameRoomRules.translate("On your Gift turn you distribute one more card than there are players: three, four or five. Reveal one card at a time to yourself and decide its destination before the next appears. Exactly one card must go into your own hand and one into the face-down Auction pile. All the others go face up into the public area."),
            GameRoomRules.translate("After you finish distributing, the other players each choose one public card, starting with the next seat. In a four-player game, you therefore keep one, reserve one for auction and let the other three players choose from the three public cards. Then the next player distributes gifts. Continue until the gift deck is exhausted."),
            GameRoomRules.translate("Your own hand is private. Everyone sees cards taken publicly or won at auction, but not the cards somebody secretly kept while distributing gifts. A public standing can therefore be incomplete: a player may have more category strength than the visible cards suggest.")),
          rule_section(:church, GameRoomRules.translate("Church cards change the prizes"),
            GameRoomRules.translate("A Church card acts as soon as someone acquires it, whether as their gift, a public choice or an auction purchase. Pause the current activity, choose its effect and discard the Church card. Merely sending it to the Auction pile does not activate it yet."),
            GameRoomRules.translate("Depending on the card, raise one die, lower one, raise two different dice, lower two different dice, or choose either direction for one die. Every change is by one point and must stay within 1\u20136. A two-die card cannot move the same die twice, and cannot be used on just one die. You may decline the whole effect instead. Raising a category you expect to win or lowering a rival's prize can change the final result.")),
          rule_section(:auction, GameRoomRules.translate("Bid in gold, or bid with cards for gold"),
            GameRoomRules.translate("The Auction pile is shuffled and its cards are offered one by one. Starting after the auction leader, players bid or pass in turn. A bid must be at least one and higher than the previous bid. Passing removes you from this card's auction. When only the highest bidder remains, they must pay. If nobody bids, the card is discarded."),
            GameRoomRules.translate("For a category or Church card, bid an amount of Gold and pay with Gold cards. There is no change. If you bid 4 but pay with two Gold cards worth 3 each, you spend 6. For a Gold card, bid a number of cards instead: a bid of 2 means giving up two hand cards, which may be of any type. Choose the payment carefully, because useful library cards can also be spent this way."),
            GameRoomRules.translate("You may bid more than you can pay. This is a bluff, not a free purchase. If you cannot or will not pay after winning, a penalty applies and the card is auctioned again without you. Players who merely passed may return to this restarted auction; players barred for not paying remain excluded from that card.")),
          rule_section(:penalty, GameRoomRules.translate("Choose the cost of an unpaid bid"),
            GameRoomRules.translate("Penalty for an unpaid bid has two settings. Medieval bluff, the default, discards one random card from the nonpayer's hand. Full penalty gives one random hand card to each other player, in order starting after the nonpayer, until everyone has received one or the hand is empty. Neither setting lets the nonpayer keep the auctioned card.")),
          rule_section(:result, GameRoomRules.translate("Turn category leads into victory points"),
            GameRoomRules.translate("After the last auction is settled, total each player's cards in every category. The highest total wins that category's die. A tied total is decided by the card letter closest to A in that category. A category nobody holds awards nothing. Add the faces of the dice you won to obtain your victory points; card values themselves are not added again."),
            GameRoomRules.translate("Most victory points wins. If tied, compare remaining Gold. If still tied, compare the Monk total and then its best letter, followed in the same way by Pigments, Forbidden Tomes, Holy Books and Manuscripts. If every comparison remains equal, the game is drawn. There is no separate score target or series of rounds in Biblios.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: browse the available cards or actions."),
            GameRoomRules.translate("Enter: choose a destination, card or effect; during payment, submit the packet."),
            GameRoomRules.translate("Shift+Enter: select or unselect a card for payment."),
            GameRoomRules.translate("Escape: clear the payment packet."),
            GameRoomRules.translate("R: enter your bid."),
            GameRoomRules.translate("L: read your library."),
            GameRoomRules.translate("Ctrl+L: browse your library by category."),
            GameRoomRules.translate("C: read the Scriptorium."),
            GameRoomRules.translate("Shift+C: read standings based on publicly taken cards."),
            GameRoomRules.translate("G: read your Gold."),
            GameRoomRules.translate("P: read the public space."),
            GameRoomRules.translate("B: read the current auction."),
            GameRoomRules.translate("S: read final scores after the game."),
            GameRoomRules.translate("Z: next card usable for payment, without selecting or paying."),
            GameRoomRules.translate("Shift+Z: previous card usable for payment, without selecting or paying."),
            GameRoomRules.translate("T: read whose turn it is."))
        ]
      end
    end
    include GeneratedRulebook
  end
end
