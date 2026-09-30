# Generated from tools/data/rulebooks/poker.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class Poker
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:chips, GameRoomRules.translate("Win the pot, keep your chips"),
            GameRoomRules.translate("Poker is played by two to eight people with a standard 52-card deck. Everyone starts with the same number of chips: 1000 unless the table owner chooses another amount from 100 to 100000. Chips placed during a hand form the pot. You win it either by showing the strongest hand or by being the only player who has not folded."),
            GameRoomRules.translate("One hand is not the whole game. After its pots have been paid out, players with no chips are eliminated, the dealer position moves on and another hand begins. The last player with chips wins the game. Committing all your chips does not eliminate you while the hand is still being played.")),
          rule_section(:holdem, GameRoomRules.translate("Texas Hold'em: two cards and a shared board"),
            GameRoomRules.translate("In the default variant, each player receives two private cards. First you bet without any cards on the board. The flop then reveals three community cards, followed by another betting round. The turn adds one card and another betting round; the river adds the fifth and final community card, followed by the last betting round. The game announces each stage and the newly revealed cards."),
            GameRoomRules.translate("At showdown, your hand is the best five-card combination you can make from your two cards and the five on the board. You may use both private cards, just one, or neither. For example, if the best five cards are all on the board, everyone still contesting that pot has access to the same combination.")),
          rule_section(:draw, GameRoomRules.translate("Five-card draw: improve your own hand"),
            GameRoomRules.translate("Five-card draw has no community cards. Everyone receives five private cards, then plays through a betting round, one exchange and a second betting round. Finally, the remaining hands are compared. During the exchange you may keep everything or replace up to three cards. Allow exchanging all five cards raises that limit to five; it does not add another exchange. Folded players no longer take part, but all-in players may still exchange."),
            GameRoomRules.translate("The optional Jacks or better rule restricts opening the first betting round: you need at least a pair of jacks or a stronger combination, such as two pairs. Once someone has opened, a weaker hand may call. This restriction does not apply to the second betting round. Both this option and exchanging all five cards are off by default.")),
          rule_section(:betting, GameRoomRules.translate("What your betting choices mean"),
            GameRoomRules.translate("Check means paying nothing and staying in the hand; it is possible only when you owe nothing to the current bet. Call pays the difference between your contribution in this betting round and the current bet. Fold gives up the hand: chips already paid stay in the pot and you cannot win them back in this hand. Raise first matches the bet, then increases it for everyone else."),
            GameRoomRules.translate("R asks for the raise above the call, not the total number of chips you will pay. If you owe 20 and enter 30, you pay 50: 20 to call and 30 to raise. The minimum full raise is the size of the previous full raise, starting from the big-blind unit. With nothing to call, the entered amount is your opening bet. An amount outside the allowed range is rejected without placing a bet."),
            GameRoomRules.translate("All-in puts in your remaining chips, subject to the betting limits. Other players still have to respond. If you cannot afford a full call, you may call with everything you have. An all-in smaller than a full raise does not normally let players who already acted raise again; several small increases must add up to a full raise before that right returns. If nobody can continue betting, the game completes the board where needed and compares the hands.")),
          rule_section(:hands, GameRoomRules.translate("Which hand wins?"),
            GameRoomRules.translate("From weakest to strongest: high card; one pair; two pairs; three of a kind; straight; flush; full house; four of a kind; straight flush. A pair is two cards of one rank. A straight is five consecutive ranks, regardless of suit; a flush is five cards of one suit. A full house combines three of one rank with two of another. A straight flush meets both the straight and flush conditions."),
            GameRoomRules.translate("When the types match, compare the ranks forming the combination, then the remaining cards, called kickers. Suits never break a tie. An ace is normally high, but A-2-3-4-5 is the lowest straight. G says No combination when you only have a high card; that does not mean your cards are ignored at showdown. Equal best five-card hands split the pot."),
            GameRoomRules.translate("A small all-in can win only the money matched by that player's contribution. Extra investments form side pots for the other eligible players. For example, with contributions of 50, 100 and 100, the first 150 can be won by all three; the remaining 100 is contested only by the last two. Each pot is settled separately. Any odd chips in a split go clockwise to tied winners, starting to the left of the dealer.")),
          rule_section(:limits, GameRoomRules.translate("Choosing the betting limits"),
            GameRoomRules.translate("No limit, the default, allows any legal raise up to your stack. Pot limit allows a raise above the call up to the pot after adding that call. Half-pot limit uses half of that amount, but never sets the ceiling below a minimum legal raise. Your remaining stack is still the final limit. Fixed limit uses a raise equal to the current big blind throughout the hand. Unlike some poker rules, our fixed-limit amount does not double in later betting rounds."),
            GameRoomRules.translate("You may also enable a cap on raises per betting round. The cap defaults to 3 and can be 1\u201310. It is shared by the whole table, not a separate allowance for every player, and resets when the next betting round starts. Without this option there is no numerical cap on raises.")),
          rule_section(:clock, GameRoomRules.translate("Time to make your decision"),
            GameRoomRules.translate("Thinking time is off by default. In either variant, the table owner may allow 1\u2013600 seconds for each betting decision and, in five-card draw, for each player's exchange. If you run out of time, you fold, even when checking would have cost nothing. Chips already committed remain in the pot; no bet or card exchange is chosen for you. Each new decision gets the full time allowance."),
            GameRoomRules.translate("There is one exception during the exchange: if you have already gone all-in, running out of time keeps all your cards without exchanging any. You are not folded and still take part in the showdown for the pots you are entitled to win.")),
          rule_section(:stakes, GameRoomRules.translate("Blinds and ante put chips into play"),
            GameRoomRules.translate("Hold'em uses blinds: forced bets made before seeing the hand develop. The small blind defaults to 5 and the big blind to 10. Both must be positive, and the big blind cannot be smaller. Five-card draw normally uses an ante of 5 from everyone instead. Its amount must be positive and no greater than the starting stack. Use blinds in five-card draw replaces that ante with blinds. Even with ante, the base big-blind value supplies the minimum betting unit."),
            GameRoomRules.translate("When blinds are used, you can leave them unchanged, increase them after a chosen number of hands, or increase them after a number of minutes. The default doubles them every five hands. The interval accepts 1\u2013100 hands or minutes and the multiplier 2\u201310. A change takes effect only at the start of a new hand, never halfway through a bet.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("C: check or call."),
            GameRoomRules.translate("F: fold."),
            GameRoomRules.translate("R: enter your raise above the call."),
            GameRoomRules.translate("A: go all-in."),
            GameRoomRules.translate("S: read your stack."),
            GameRoomRules.translate("Shift+S: read the other players' stacks."),
            GameRoomRules.translate("V: read the amount needed to call."),
            GameRoomRules.translate("P: read the total pot."),
            GameRoomRules.translate("I: read your investment in this hand."),
            GameRoomRules.translate("H: read who is still in and who has folded."),
            GameRoomRules.translate("L: read the blinds."),
            GameRoomRules.translate("D: read your cards."),
            GameRoomRules.translate("E: read the community cards."),
            GameRoomRules.translate("G: read your best current combination."),
            GameRoomRules.translate("Arrows: during exchange, choose a card."),
            GameRoomRules.translate("Shift+Enter: during exchange, select or unselect the current card."),
            GameRoomRules.translate("Enter: exchange the selected packet, also including the current card."),
            GameRoomRules.translate("Escape: cancel a bid input or card selection."),
            GameRoomRules.translate("T: read whose turn it is."),
            GameRoomRules.translate("Shift+C: during exchange, sort by suit or colour; press again to reverse the order."),
            GameRoomRules.translate("Shift+H: during exchange, sort by rank or value; press again to reverse the order."),
            GameRoomRules.translate("Shift+M: during exchange, restore the order in which cards were received."),
            GameRoomRules.translate("1: read private card 1."),
            GameRoomRules.translate("2: read private card 2."),
            GameRoomRules.translate("3: in Hold'em, read community card 1; in draw poker, read private card 3."),
            GameRoomRules.translate("4: in Hold'em, read community card 2; in draw poker, read private card 4."),
            GameRoomRules.translate("5: in Hold'em, read community card 3; in draw poker, read private card 5."),
            GameRoomRules.translate("6: in Hold'em, read community card 4."),
            GameRoomRules.translate("7: in Hold'em, read community card 5."))
        ]
      end
    end
    include GeneratedRulebook
  end
end
