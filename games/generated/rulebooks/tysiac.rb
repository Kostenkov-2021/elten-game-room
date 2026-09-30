# Generated from tools/data/rulebooks/tysiac.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class Tysiac
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:auction, GameRoomRules.translate("Win the auction, then fulfil your promise"),
            GameRoomRules.translate("The 1000 card game is played individually, by two or three people. Choose the player count when creating the table; the default is three. The deck has 24 cards: nine, jack, queen, king, ten and ace in every suit. Players bid for the right to take a talon. The winning bidder promises to collect at least the contracted number of points during the deal."),
            GameRoomRules.translate("The player after the dealer opens at no less than 100. Later bids rise in steps of five. Passing removes you from this auction, not from the game. You may bid up to 120 plus the values of the marriages you currently hold, with an overall maximum of 400. A marriage is a king and queen of the same suit."),
            GameRoomRules.translate("With three players, each receives seven cards and the three remaining cards form one talon. The auction winner takes those three revealed cards, then gives one card to each opponent in the announced order. Each recipient learns only their own card. Everyone then has eight cards, to be played in eight tricks."),
            GameRoomRules.translate("Once the cards have been given away or set aside, the bidder can raise the final contract within the limit allowed by the marriages still held. Playing the first card accepts the current contract, so a second bid is not compulsory.")),
          rule_section(:two_players, GameRoomRules.translate("Two players: choose one of two talons"),
            GameRoomRules.translate("The two-player variant uses two separate, face-down talons. Choose two or three cards in each talon in the table settings. With two-card talons, each player is dealt ten cards. With three-card talons, each receives nine. Three cards is the default. The auction works as described above."),
            GameRoomRules.translate("The auction winner chooses the first or second talon without seeing either one's contents. Only the chosen talon is then revealed and added to the winner's hand. The other remains face down. The bidder now sets aside as many cards as were taken, one at a time, using Enter on a card. These discards are not shown to the opponent, and no card is passed to them. The players finish with ten cards each for two-card talons, or nine each for three-card talons."),
            GameRoomRules.translate("The checkbox Set-aside cards go to the last trick winner is enabled by default. It awards the card points from both the unchosen talon and the bidder's discards to whoever takes the last trick, before checking the contract. Thus all 120 card points remain in play. It does not award marriages from those cards or add the cards to the winner's hand. If the checkbox is disabled, nobody scores those cards, so fewer than 120 card points may be available in tricks."),
            GameRoomRules.translate("For example, suppose the unchosen talon contains an ace and a nine, and the bidder sets aside a king and a jack. Those four cards are worth 17 points. With the checkbox enabled, winning the last trick gives its winner these 17 points in addition to the points in the trick itself. With it disabled, those 17 points are not awarded.")),
          rule_section(:tricks, GameRoomRules.translate("Taking tricks and declaring marriages"),
            GameRoomRules.translate("The bidder leads the first trick. Everyone plays one card, and the trick's winner leads next. A trick contains two cards with two players, or three cards with three. You must follow the first card's suit if possible. If you have none of that suit, you must use a trump if a trump suit has been established and you hold one. Only otherwise may you discard any card. You do not have to beat a higher card merely because you can."),
            GameRoomRules.translate("The order from strongest to weakest is ace, ten, king, queen, jack, nine. A trump beats every non-trump. With no trump in the trick, the highest card of the led suit wins. At the beginning of the deal there is no trump suit."),
            GameRoomRules.translate("After the first trick, a player leading a trick may declare a marriage by playing its king or queen while still holding the matching partner. The declared suit becomes trump immediately. Hearts add 100 points, diamonds 80, clubs 60 and spades 40. A later marriage changes trump again. Simply owning the pair, or playing it without the declaration, does not award that bonus.")),
          rule_section(:points, GameRoomRules.translate("Points in cards are not the same as the score you receive"),
            GameRoomRules.translate("An ace is worth 11, a ten 10, a king four, a queen three, a jack two and a nine zero. The cards total 120 points. Add any declared marriages before checking the bidder's contract."),
            GameRoomRules.translate("A successful bidder receives exactly the contract value, not all the points collected. A failed bidder loses the contract value. Defenders add their collected points rounded to the nearest five. The bidder's success is checked before rounding: 118 points do not fulfil a contract of 120."),
            GameRoomRules.translate("The target is normally 1000. You can choose another multiple of five, at least 200. Reaching the target ends the game, subject to the barrel rules below. There are no team or alternative-deck settings.")),
          rule_section(:barrel, GameRoomRules.translate("Near the target: the barrel"),
            GameRoomRules.translate("When your score reaches the interval from 120 below the target to just below the target, it is set to exactly 120 below and you go onto the barrel. At the usual target this means 880. Defender points no longer increase your score there. You have three deals to win and fulfil a contract of at least 120."),
            GameRoomRules.translate("Failing a contract on the barrel subtracts its normal value and takes you off. Using up all three chances without success costs 120 and also takes you off. If someone else takes the talon and surrenders before play, that deal does not use one of your chances. You cannot surrender your own contract while on the barrel. A different target moves the barrel threshold with it."),
            GameRoomRules.translate("The game announces when someone goes onto the barrel and records it in the history. S reads scores and marks the players currently on the barrel. Shift+S also tells you how many barrel chances they have left.")),
          rule_section(:penalties, GameRoomRules.translate("Surrendering and collecting no points"),
            GameRoomRules.translate("After seeing the talon but before giving away or setting aside the first card, the bidder may surrender, unless on the barrel. Each defender receives at least 60, or half the contract if that is higher, rounded upwards to five. With two players there is only one defender, receiving the same award. No last-trick award applies to a surrendered deal. The bidder normally receives zero. Every third surrender additionally costs the bidder 120 points."),
            GameRoomRules.translate("Collecting exactly zero unrounded points in three played deals costs 120. A small result that merely rounds to zero does not count as a zero deal. These zeroes are not accumulated while you are on the barrel.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: choose a bid, talon card or trick card."),
            GameRoomRules.translate("Enter: confirm the current choice; on a card, play or choose a marriage."),
            GameRoomRules.translate("Shift+Enter: declare a legal marriage directly; without one, do not play."),
            GameRoomRules.translate("B: change the final contract before playing the first card."),
            GameRoomRules.translate("H: read your hand."),
            GameRoomRules.translate("C: read the trick cards."),
            GameRoomRules.translate("Ctrl+C: browse the trick cards."),
            GameRoomRules.translate("F: read the trump suit."),
            GameRoomRules.translate("Shift+S: read zeroes, surrenders and barrel chances."),
            GameRoomRules.translate("Z: next legal trick card; a possible marriage prevents automatic play."),
            GameRoomRules.translate("Shift+Z: previous legal trick card; a possible marriage prevents automatic play."),
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
