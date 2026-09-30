# Generated from tools/data/rulebooks/scientific_war.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class ScientificWar
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:setup, GameRoomRules.translate("Scientific War is a card game for two to eight players."),
            GameRoomRules.translate("It is based on War, but you choose which card to play, so bluff and strategy matter. There is no random deal. Every player gets all thirteen cards of one suit, from two to ace, plus one joker, so everyone starts with the same cards. Two players play with hearts and spades. With more than four players a second deck is added, so some suits appear twice."),
            GameRoomRules.translate("You hold your cards in your hand and choose which one to play. The cards in your hand are always listed from the lowest to the highest, with the joker last. The cards you win go to a separate pile.")),
          rule_section(:trick, GameRoomRules.translate("Choosing and revealing"),
            GameRoomRules.translate("In each trick everyone chooses a card at the same time. Nobody can see your card until everyone has chosen; then all the cards are turned face up together. Do not leave the table before your card is revealed, because the trick waits for it."),
            GameRoomRules.translate("The player with the strongest card wins the trick and puts all its cards on their pile. Normally the ace is the strongest card and the two the weakest. Suits do not matter."),
            GameRoomRules.translate("When your hand is empty after a trick, you pick up your pile and it becomes your new hand. If your pile is empty too, you are out of the game.")),
          rule_section(:war, GameRoomRules.translate("War"),
            GameRoomRules.translate("If two or more strongest cards are equal, there is a war and nobody takes the trick. The cards stay on the table, and whoever wins the next trick takes them as well. If there are several wars in a row, more and more cards wait on the table.")),
          rule_section(:powers, GameRoomRules.translate("Card powers"),
            GameRoomRules.translate("Jack, revolution: a jack reverses the card order at once, already in the trick in which it is played. The two becomes the strongest card and the ace the weakest. The next jack restores the usual order. Two jacks in the same trick cancel each other out."),
            GameRoomRules.translate("Queen, spy: in the next trick, the player who played a queen chooses last and first hears the cards the others have chosen. If two or more queens are played in the same trick, they cancel each other out."),
            GameRoomRules.translate("Three: in the next trick, the player who played a three can check how many cards each opponent has in hand. At any time, anyone can check how many cards each player has in total, in hand and on the pile."),
            GameRoomRules.translate("Eight: in the next trick, before choosing a card, the player who played an eight may swap their hand with their pile.")),
          rule_section(:joker, GameRoomRules.translate("Joker"),
            GameRoomRules.translate("If the trick would end in a war, the joker prevents it and the player who played it wins the trick. If there would be no war, the joker causes one: nobody takes the trick and the cards stay on the table. If two or more jokers are played in the same trick, none of them has any effect.")),
          rule_section(:ending, GameRoomRules.translate("End of the game"),
            GameRoomRules.translate("The last player who still has cards wins. The table has a trick limit from 20 to 100, 50 by default. When it is reached, the player with the most cards wins; if several players have the same highest number, the game is a draw. A very long game with many players may end a little earlier in the same way, because a table can store only a limited number of moves."),
            GameRoomRules.translate("You can save the game only at the start of a trick, before any person has chosen a card, because until the cards are revealed, nobody else knows your card. Bots use their own cards and public information from earlier tricks to choose a play. A bot that is the spy also takes the revealed cards into account, just like a person; it cannot see other players' secret choices.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Enter: play the selected card."),
            GameRoomRules.translate("Z: move to the next card in your hand; if it is your only card, play it."),
            GameRoomRules.translate("Shift+Z: move to the previous card in your hand; if it is your only card, play it."),
            GameRoomRules.translate("C: use your card power: read the chosen cards as the spy, read the hand sizes after a three, or swap your hand with your pile after an eight."),
            GameRoomRules.translate("E: read how many cards each player owns."),
            GameRoomRules.translate("T: read who has already chosen a card."),
            GameRoomRules.translate("R: read the current rules."),
            GameRoomRules.translate("V: read the result of the last trick."))
        ]
      end
    end
    include GeneratedRulebook
  end
end
