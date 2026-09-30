# Generated from tools/data/rulebooks/ninety_nine.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class NinetyNine
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:tokens, GameRoomRules.translate("Three cards and one shared total"),
            GameRoomRules.translate("In 99, two to eight players change a shared total by playing cards. You want to protect your tokens and make other players lose theirs. Each round starts with three cards per player and a total of zero. After your play, if the round continues, you automatically receive a replacement card."),
            GameRoomRules.translate("The dealer changes between rounds, and the next active player starts. Seven or eight players use two decks. When the drawing pile runs out, discards are shuffled back in; this does not replace the cards people are holding. A new round deals new hands and resets the shared total, but token balances carry over.")),
          rule_section(:cards, GameRoomRules.translate("What your card will do"),
            GameRoomRules.translate("Cards from 3 to 8 add their printed value. Queens and kings add 10. A nine leaves the total unchanged, which can be useful when adding points would be dangerous."),
            GameRoomRules.translate("An ace gives you a choice of adding 1 or 11. A ten lets you add or subtract 10, but you cannot go below zero. The game asks for that choice before playing the card."),
            GameRoomRules.translate("A two normally doubles the total. However, if the total is even and greater than 49, it halves it instead: 60 becomes 30. A jack adds 10 and skips the next player. With two players, this gives its author another turn. A four still adds four, but also reverses direction when at least three players remain.")),
          rule_section(:thresholds, GameRoomRules.translate("The important totals: 33, 66 and 99"),
            GameRoomRules.translate("Increasing the total to exactly 33 or 66 makes every other active player lose one token. Jumping upwards past one of these thresholds makes you lose one token instead. Crossing both costs you two. For example, going from 30 to 33 charges your opponents, while going from 30 to 35 charges you."),
            GameRoomRules.translate("These penalties depend on an increase. Subtracting from 43 to 33, or leaving 33 unchanged with a nine, does not charge anyone. Doubling 33 to 66 does count as an increase to an exact threshold."),
            GameRoomRules.translate("Making exactly 99 wins the round and costs every other active player two tokens. Going above 99 loses the round and costs you two additional tokens, on top of any 33 or 66 crossing penalties from that play. The next round then starts with the players still in the game."),
            GameRoomRules.translate("Zero tokens does not itself eliminate you. You drop out only when a later penalty costs more than you can pay. If you have one token and lose one, you stay; if you must then pay another, you are out. The last active player wins the game.")),
          rule_section(:clock, GameRoomRules.translate("When your time runs out"),
            GameRoomRules.translate("Thinking time is off by default. The table owner may set a limit of 1\u2013600 seconds for each turn. If you do not act in time, you lose one token and the turn passes to the next player. Your cards and the shared total stay unchanged: the game does not choose a card for you or start a new round. As with other penalties, paying your last token does not eliminate you; failing to pay a later penalty does.")),
          rule_section(:options, GameRoomRules.translate("Tokens and bot knowledge"),
            GameRoomRules.translate("Starting tokens defaults to 9 and can be changed to another positive number. Omniscient bots is off by default. Enabling it deliberately lets bots see all current hands while deciding their moves; ordinary bots use their own cards and public play. It changes the information available to the bot, not card effects or penalties.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: browse cards."),
            GameRoomRules.translate("Enter: play the card or choose the value of an ace or ten."),
            GameRoomRules.translate("Escape: cancel a value choice without playing."),
            GameRoomRules.translate("H: read your hand."),
            GameRoomRules.translate("C: read the shared total."),
            GameRoomRules.translate("S: read everyone's tokens."),
            GameRoomRules.translate("Z: next legal card; only move the cursor if a value choice is needed."),
            GameRoomRules.translate("Shift+Z: previous legal card; only move the cursor if a value choice is needed."),
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
