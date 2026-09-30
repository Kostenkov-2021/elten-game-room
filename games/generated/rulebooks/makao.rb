# Generated from tools/data/rulebooks/makao.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class Makao
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:matching, GameRoomRules.translate("Get rid of your hand"),
            GameRoomRules.translate("Makao is for two to eight players. The first person with an empty hand wins the game. You normally begin with five cards from a standard deck, with two jokers added only in the appropriate profile. The first card on the table is not a two, three, four, ace, king or joker. Play starts after the dealer and continues in one fixed direction."),
            GameRoomRules.translate("On your turn, play a card matching the suit or rank of the table card. For example, on an eight of hearts you may play another heart or an eight of another suit. Some special cards can change this rule. A pending penalty or requested rank can also restrict what you may play."),
            GameRoomRules.translate("You can play several cards as one packet if they share a rank. Only its first card has to start a legal move; later cards may be of other suits. Choose the order deliberately, because the last card becomes the new table card. A packet is one move, not several turns, and a joker must represent the same rank as the rest."),
            GameRoomRules.translate("When you have no legal starting card, draw one. The three ready-made profiles also allow you to draw voluntarily instead of playing a card you already have. Custom rules has an Allow drawing with a playable card checkbox, enabled by default, which you can turn off. If the drawn card is playable and playing a drawn card is enabled, you may play it immediately, also as part of a packet, or press Space again to end your turn without drawing another card. Otherwise the turn ends automatically, even if another card in your hand could be played. This choice does not cancel a drawing or waiting penalty. If the drawing pile runs out, discards other than the top card are recycled.")),
          rule_section(:penalties, GameRoomRules.translate("Drawing penalties and waiting turns"),
            GameRoomRules.translate("A two adds two cards to the next player's penalty, and a three adds three. Instead of paying, the attacked player can answer with a permitted attacking card. The debt then passes on and grows. With mixed twos and threes enabled, a two answered by a three makes five cards. With it disabled, the responding rank must match the attack."),
            GameRoomRules.translate("If you have no legal defence, the program takes the whole drawing penalty for you and ends your turn. A drawing attack targets the next seat, including a player who is waiting after a four. A waiting player cannot defend: they draw automatically, using up one of their waiting turns. The attack does not bounce back to its author merely because the next player is waiting."),
            GameRoomRules.translate("A four makes the next player wait. With accumulating fours enabled, another four or a packet of fours passes on a larger waiting penalty. The player who accepts it waits that many turns, including the current one; later waiting turns are skipped automatically. If accumulation is disabled, a four simply skips one turn and cannot be answered by another four."),
            GameRoomRules.translate("Attacking kings introduces a separate five-card attack. The king of spades starts it; the king of hearts can answer it and add five more. Thus spades followed by hearts makes the next player draw ten, unless they defend again. It does not reverse play. The other kings are ordinary cards, and a king attack is not combined with a two-or-three attack.")),
          rule_section(:special, GameRoomRules.translate("Changing the card that others must follow"),
            GameRoomRules.translate("Ace changes suit lets you start an ordinary move with an ace regardless of the table card and choose a suit. It is not a way out of a pending drawing or waiting penalty. With the option off, an ace follows the ordinary matching rule."),
            GameRoomRules.translate("Jack requests a rank lets the player using a jack request a value from five to ten. The next player must meet that request rather than merely follow suit. With the option off, jacks are ordinary matching cards. Queen is universal separately lets a queen start an ordinary move on any table card, but it does not defend a pending penalty."),
            GameRoomRules.translate("Use two jokers adds two cards that can represent an ordinary or special card. You choose what the joker represents when playing it. It only defends a penalty if the represented card would be a legal defence. Representing an ace, jack or king uses its special effect only when that effect is enabled at the table.")),
          rule_section(:profiles, GameRoomRules.translate("Choose a profile, or make your own"),
            GameRoomRules.translate("Simple Makao is the default. It enables mixed twos and threes, accumulating fours, suit-changing aces and playing a drawn card. There are no jokers, jack requests, universal queens or attacking kings. Polish extended Makao adds jack requests, universal queens and attacking kings, but still no jokers."),
            GameRoomRules.translate("Makao with jokers adds two jokers and attacking kings to the simple rules. Jack requests and universal queens stay off, and the starting hand is fixed at five. Custom rules lets you set these switches individually. The custom choices are remembered locally for your next custom table; they do not change another person's room."),
            GameRoomRules.translate("Outside the fixed joker profile, the starting hand can have three to fifteen cards, normally five. There must be enough cards for all players and the first table card. The penalty for forgetting Makao is independent of the profile: one to ten cards, normally one."),
            GameRoomRules.translate("When one card remains, announce Makao. Another player may catch an omission before your next turn and make you draw the configured penalty. You can announce or catch Makao during someone else's turn, including a bot's delay. Playing your last card wins immediately; this game does not run a points-elimination tournament.")),
          rule_section(:clock, GameRoomRules.translate("When time runs out"),
            GameRoomRules.translate("Thinking time is optional, with zero meaning no limit and 1\u2013600 seconds available. On expiry, a player accepts a pending waiting penalty or draws the whole pending card penalty. Otherwise they draw one penalty card, even if they already drew normally in that turn. The turn ends without playing a card. Drawing, saying Makao and catching another player do not restart the clock.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: browse cards."),
            GameRoomRules.translate("Enter: play the current card or prepared packet; choose a declaration if needed."),
            GameRoomRules.translate("Shift+Enter: add or remove the current card from the packet; selection order is play order."),
            GameRoomRules.translate("P: read the prepared packet."),
            GameRoomRules.translate("Shift+P: clear the prepared packet."),
            GameRoomRules.translate("Space: draw, or end the turn after drawing."),
            GameRoomRules.translate("U: say Makao, including during another player's or bot's turn."),
            GameRoomRules.translate("Shift+U: catch a player who did not say Makao."),
            GameRoomRules.translate("C: read the table card and declaration."),
            GameRoomRules.translate("G: read the pending penalty."),
            GameRoomRules.translate("D: read your hand."),
            GameRoomRules.translate("E: read each player's card count."),
            GameRoomRules.translate("Z: next legal card; automatic play only without a declaration or packet alternative."),
            GameRoomRules.translate("Shift+Z: previous legal card; automatic play only without a declaration or packet alternative."),
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
