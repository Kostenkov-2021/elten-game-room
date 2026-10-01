# Generated from tools/data/rulebooks/uno.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class Uno
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:hand, GameRoomRules.translate("Match a card and try to empty your hand"),
            GameRoomRules.translate("UNO is for two to eight players. Each round starts with seven cards per person. On your turn, play a card matching the current colour or the number or symbol on the top discard. On a blue seven, for example, you may play a blue card or a seven of another colour. Wild cards let you choose the next colour."),
            GameRoomRules.translate("Usually you play one card and the turn moves on. The first empty hand wins the round, although a final drawing penalty or buzzer must be resolved before points are counted. With one card left, announce UNO. Another player can catch the missing announcement in the response window, making its owner draw two cards."),
            GameRoomRules.translate("You want as few points as possible. The round winner receives zero; everyone else adds the value of cards still held. Number cards count their number, coloured action cards 20 and wild cards 50. The elimination limit is normally 500, configurable from 50 to 5000. Players reaching it leave after the round, while the others continue. The last remaining player wins the whole game.")),
          rule_section(:draw, GameRoomRules.translate("Drawing is not always the end of your turn"),
            GameRoomRules.translate("An ordinary draw takes one card. If you still have no legal card afterwards, your turn ends automatically. Otherwise you may play. When the pile runs out, discards except the top card are shuffled back for drawing; nobody loses their hand."),
            GameRoomRules.translate("Allow drawing with a playable card is on by default. Its separate limit is normally three voluntary cards per turn, from one to twenty. At the limit, another press only reports that you cannot draw; it does not secretly end the turn. If optional drawing is off, having a legal card prevents an ordinary draw."),
            GameRoomRules.translate("Draw until a playable card is off by default. If enabled, one draw action keeps taking cards until a playable card is found or the available supply ends. Penalty draws are separate: they take the amount currently owed, not this ordinary-drawing allowance."),
            GameRoomRules.translate("Skip the turn after drawing a penalty is off by default. With it on, paying a penalty always ends your turn. With it off, you may still play if your resulting hand has a legal card; otherwise the turn ends automatically. You do not have to draw again just to confirm that you cannot play.")),
          rule_section(:classic, GameRoomRules.translate("The classic deck and drawing attacks"),
            GameRoomRules.translate("Classic is the default deck: four colours, numbers from zero to nine, Skip, Reverse, Draw Two, Wild and Wild Draw Four. Skip misses the next player; Reverse changes direction and normally acts as Skip with two players. Draw Two adds two cards to a penalty, while Wild Draw Four adds four and changes colour."),
            GameRoomRules.translate("A colour-changing wild is played in two steps. First it leaves your hand and becomes the table card; then you select a colour. Nobody can intercept between those steps. A configured thinking timer is paused during this colour choice. The next player receives their full turn time once the colour is chosen."),
            GameRoomRules.translate("Draw responses, on by default, lets you pass a drawing debt on by adding another permitted drawing card. In Classic it must be the same kind: Draw Two answers Draw Two, Wild Draw Four answers Wild Draw Four. The next player owes the accumulated amount. Without this option, you must take the debt instead."),
            GameRoomRules.translate("Advanced responses requires ordinary responses and is off by default. Skip or Wild passes the debt onwards; Reverse sends it in the other direction. In No Mercy, Discard All and Skip Everyone instead cancel a pending numerical drawing penalty."),
            GameRoomRules.translate("Challenging Wild Draw Four is an optional Classic-only rule. If its author still had a card of the previous colour, a successful challenge makes them draw four instead. If the play was justified, the challenger draws six and loses the turn. The option is off by default; the game does not automatically challenge every wild.")),
          rule_section(:decks, GameRoomRules.translate("No Mercy and Flip"),
            GameRoomRules.translate("No Mercy adds coloured Draw Four and wild Draw Six, Draw Ten and Reverse Draw Four. Drawing responses stay in their family, coloured or wild, and cannot be weaker than the last attack. Reverse Draw Four also reverses direction; with two players its debt returns to the player who used it."),
            GameRoomRules.translate("No Mercy also has Skip Everyone, which gives another play; Discard All, which removes your other cards of the played colour; and Colour Roulette. Roulette makes the next player draw until a non-wild card of the chosen colour appears, then ends their turn."),
            GameRoomRules.translate("The No Mercy card limit normally removes a player from the round at 25 cards and adds 250 points. You can choose a limit from 10 to 100, or zero to disable it. This is not necessarily elimination from the whole game: the player returns next round unless their total score has reached the overall elimination limit."),
            GameRoomRules.translate("Flip uses two-sided cards. Playing Flip turns every hand and both piles over and reverses the pile order. The light side has Draw One and Wild Draw Two; the dark side has its own colours, Draw Five, Skip Everyone and wild colour drawing. Only the active side determines matching and effects. Power Games counts coloured action cards as 20 and wild cards as 50 on either side.")),
          rule_section(:speed, GameRoomRules.translate("Optional fast reactions and hand exchanges"),
            GameRoomRules.translate("Interceptions lets you play out of turn with a non-wild card identical in colour and face to the top discard. You take over play, subject to that card's effect; intercepting with a drawing attack does not make you pay your own attack. Super interceptions relaxes the colour requirement but still requires the same face. Both options are off by default, and Super requires ordinary interceptions."),
            GameRoomRules.translate("With interceptions enabled, trying a nonmatching card during someone else's turn says Too late and adds three penalty points. The card stays in your hand. This also applies during a bot's pause, without a special exemption for mistaken key presses. It does not apply to ordinary wrong moves on your own turn or to buzzer response windows. Score-limit elimination is checked at the round's end."),
            GameRoomRules.translate("Straights, off by default, lets you follow your own number-card play with consecutive numbers of the same colour, going up or down. For example, red eight, seven, six. Each card is a separate play. You can continue only until another player plays or intercepts; there is no separate timed straight window, and you cannot start the sequence out of turn."),
            GameRoomRules.translate("Zero and seven hand swapping is off by default. A seven exchanges your hand with a chosen opponent; a zero passes all active hands in the direction of play. Buzzer cards, also off, adds eight universal buzzer cards to Classic or No Mercy, not Flip. After a buzzer, everyone still active responds with B and the last responder draws two. Any card may follow a buzzer."),
            GameRoomRules.translate("Thinking time is unlimited at zero, or can be set from one to 300 seconds. Expiry takes the pending drawing penalty, or one penalty card if there is no pending penalty, then ends the turn. This penalty also applies when you have already drawn voluntarily. Buzzer responses and colour selection pause the timer. The game does not interrupt play with automatic time-remaining announcements.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: browse cards or colour choices."),
            GameRoomRules.translate("Enter: play the card, or confirm the requested colour or player."),
            GameRoomRules.translate("Space: draw a card or accept the pending draw penalty."),
            GameRoomRules.translate("U: say UNO or catch a missing UNO."),
            GameRoomRules.translate("B: respond to the buzzer."),
            GameRoomRules.translate("F: challenge Wild Draw Four."),
            GameRoomRules.translate("C: read the top card."),
            GameRoomRules.translate("V: read the current colour."),
            GameRoomRules.translate("E: read each player's card count."),
            GameRoomRules.translate("G: read the pending penalty."),
            GameRoomRules.translate("Z: next legal card on your turn; disabled with straights, interceptions or buzzer cards."),
            GameRoomRules.translate("Shift+Z: previous legal card on your turn; disabled with straights, interceptions or buzzer cards."),
            GameRoomRules.translate("Shift+D: restore acquisition order."),
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
