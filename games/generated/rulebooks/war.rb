# Generated from tools/data/rulebooks/war.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class War
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:battle, GameRoomRules.translate("Play your top card"),
            GameRoomRules.translate("War is a card game for two to eight players. The whole deck is dealt out, and every player keeps their cards in a face-down pile. Players do not choose cards: in each battle, everyone plays the top card of their own pile, one after another."),
            GameRoomRules.translate("The highest card wins the battle and takes all the cards from the table. Aces are highest, then kings, queens, jacks, tens and so on down to the lowest card in the deck. Suits do not matter. The cards taken go to the bottom of the winner's pile in random order.")),
          rule_section(:war, GameRoomRules.translate("War: equal highest cards"),
            GameRoomRules.translate("If two or more players share the highest card, a war starts between them. Each of them places one hidden card and then plays the next card face up. The highest of the new cards takes everything from the table, including the hidden cards and the cards of players who did not take part in the war. If the new cards are equal again, the war continues in the same way. When a war is won, the winner hears every hidden card taken, first the opponents' and then their own, and then the other cards from the table."),
            GameRoomRules.translate("A player with only one card left plays it face up without a hidden card. A player with no cards cannot continue the war; if only one participant can continue, they take the table. If nobody can continue, the cards stay on the table and go to the winner of the next battle.")),
          rule_section(:deck, GameRoomRules.translate("Choosing the deck"),
            GameRoomRules.translate("The Deck option chooses a short deck of 24 cards, from nine to ace, or a full deck of 52 cards, from two to ace. The short deck is the default and gives a much quicker game. If the cards cannot be divided equally, some players start with one card more.")),
          rule_section(:ending, GameRoomRules.translate("End of the game"),
            GameRoomRules.translate("A player who has no cards left after a battle is out of the game. The last player with cards wins."),
            GameRoomRules.translate("War can last very long, so the table has a battle limit, from 20 to 300 battles, 20 by default. When the limit is reached, the player with the most cards wins. If several players have the same highest number of cards, the game ends in a draw.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Enter: play your top card."),
            GameRoomRules.translate("Space: play your top card."),
            GameRoomRules.translate("C: read the cards on the table, your own first, then each opponent's."),
            GameRoomRules.translate("E: read each player's card count."),
            GameRoomRules.translate("V: read the result of the last battle."),
            GameRoomRules.translate("T: read whose turn it is."),
            GameRoomRules.translate("Ctrl+T: read the number of the current battle and the battle limit."))
        ]
      end
    end
    include GeneratedRulebook
  end
end
