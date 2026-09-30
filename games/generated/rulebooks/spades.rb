# Generated from tools/data/rulebooks/spades.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class Spades
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:contracts, GameRoomRules.translate("Promise a number of tricks, then try to take them"),
            GameRoomRules.translate("A trick is one card played by each player in turn. One player wins those cards and starts the next trick. In Spades, you first promise how many tricks you will win. Taking too few is expensive, but taking far too many can hurt as well. Spades are always trumps: they beat cards of the other suits."),
            GameRoomRules.translate("Game Room supports three to six players. Three players receive 17 cards each after removing one two; four receive 13 from the full deck; five receive 10 after removing two twos; six receive eight after removing all twos. Cards rank from two up to ace. The dealer rotates, and the next player starts both bidding and the first trick."),
            GameRoomRules.translate("Individual play is the default. Four players may form two pairs; six may form three pairs or two teams of three. At three or five players everyone plays individually. Teams share a score. Their members are assigned before starting, using the proposed alternating seats or the master's chosen valid arrangement."),
            GameRoomRules.translate("Each player declares a number from zero to the size of their hand. You do not have to outbid the previous player. In a team, partners' positive declarations add together into one contract. A declaration of zero, called nil, remains that person's separate promise to win no tricks.")),
          rule_section(:tricks, GameRoomRules.translate("Following suit and breaking spades"),
            GameRoomRules.translate("The first card of a trick sets its suit. You must follow that suit if you can. Game Room has one exception: if the ace is your only spade, you may keep it when spades are led and play another suit instead. When you cannot follow suit, you may play any card; you are not forced to use a trump."),
            GameRoomRules.translate("The highest spade wins. If nobody played a spade, the highest card of the led suit wins. A high card in another suit does not win merely because it is high. For example, an ace of hearts cannot beat a low club in a club-led trick unless hearts were the led suit instead."),
            GameRoomRules.translate("You cannot lead with a spade until someone has used a spade on a trick led in another suit. This is called breaking spades. If your hand contains only spades, you may lead one anyway. Whoever wins a trick chooses the first card of the next.")),
          rule_section(:points, GameRoomRules.translate("Contracts, nils and bags"),
            GameRoomRules.translate("Under normal scoring, meeting a positive contract earns ten points per promised trick and one per extra trick. Missing the contract loses ten times the whole bid. A bid of four with five tricks therefore gives 41, while the same bid with three tricks gives minus 40, before any other bonuses or bag penalties."),
            GameRoomRules.translate("Extra tricks are called bags. They are already included in the score, but accumulate between deals: each set of ten also costs 100 points. A successful nil gives 100. Taking even one trick after declaring nil costs 100; in normal scoring its tricks also become bags. A failed nil's tricks do not help a partner fulfil an ordinary contract."),
            GameRoomRules.translate("There are also contract bonuses. With three or four players, a contract of one or two made exactly gives 20 extra points. A successful large contract adds ten per level starting at ten with three players, seven with four, six with five or five with six. For example, a four-player contract of eight earns an extra 20 for reaching levels seven and eight."),
            GameRoomRules.translate("The target score is a positive number, normally 300. Scores are checked after the deal. A sole leader at or above the target wins; a tie for first place means another deal. In a team game compare team scores, not individual tricks.")),
          rule_section(:variants, GameRoomRules.translate("Changing the kind of challenge"),
            GameRoomRules.translate("No Hell prevents the last bidder from making the sum of all declarations equal the number of tricks available. Someone will therefore miss a contract or take extra tricks. It is off by default."),
            GameRoomRules.translate("Quicksand replaces the normal contract calculation. An exact contract gives ten times the bid, each extra trick subtracts ten, and a missed contract costs ten for each missing trick. There are no accumulated bags or the normal small- and large-contract bonuses. Nil still gives or costs 100. This option is off by default."),
            GameRoomRules.translate("Suicide is for teams of two. At least one partner in each pair must declare nil; both may do so. A positive bid must be at least four. It changes bidding, not the chosen scoring system. Suicide is off by default and cannot be combined with No Hell."),
            GameRoomRules.translate("Omniscient bots, off by default, deliberately gives bots knowledge of every current hand. Ordinary bots use their own cards and public play. The mode does not change what cards people are allowed to play.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: browse cards."),
            GameRoomRules.translate("Enter: play the selected card."),
            GameRoomRules.translate("B: during bidding, enter your bid; otherwise read the bids."),
            GameRoomRules.translate("C: read the trick cards."),
            GameRoomRules.translate("Ctrl+C: browse the trick cards."),
            GameRoomRules.translate("F: read the led suit."),
            GameRoomRules.translate("I: read your progress in the round."),
            GameRoomRules.translate("V: read everyone's tricks taken and bids."),
            GameRoomRules.translate("S: read scores and bags."),
            GameRoomRules.translate("Z: next legal card; play it automatically if it is the only unambiguous option."),
            GameRoomRules.translate("Shift+Z: previous legal card; play it automatically if it is the only unambiguous option."),
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
