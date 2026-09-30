# Generated from tools/data/rulebooks/domino.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class Domino
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:chain, GameRoomRules.translate("Build a chain and empty your hand"),
            GameRoomRules.translate("A domino tile has two numbers, one at each end. On your turn, attach one tile to either end of the chain so that touching numbers match. For example, with 2 at the left end and 5 at the right, a 2/6 can go on the left and a 5/1 on the right. The program turns the tile the right way round. Only the two outer ends are playable; you cannot attach tiles in the middle."),
            GameRoomRules.translate("The player holding the highest dealt double starts. A double is a tile with equal numbers, such as 6/6. If no hand has a double, the highest total decides; ties use the round's rotating priority. The starter may play any tile, not necessarily the double that gave them the start. A normal round ends as soon as someone uses their last tile.")),
          rule_section(:sets, GameRoomRules.translate("A larger set means more copies and more numbers"),
            GameRoomRules.translate("Double 6 contains each pair of numbers from 0 to 6 once, including doubles: 28 tiles in all. It deals seven tiles to each of up to four players. Every other set deals ten per player. Double 9 has 55 tiles and 2\u00D7 Double 6 has 56, so these two sets allow at most five players. All the remaining sets allow up to eight players in Game Room."),
            GameRoomRules.translate("The other choices are Double 12 (91 tiles), 2\u00D7 Double 9 (110), 2\u00D7 Double 12 (182), 4\u00D7 Double 6 (112), 4\u00D7 Double 9 (220), 4\u00D7 Double 12 (364), Double 15 (136) and Double 18 (190). The number after Double is the largest number on a tile; 2\u00D7 or 4\u00D7 means two or four copies of the complete set. Undealt tiles form the boneyard, the face-down draw pile.")),
          rule_section(:drawing, GameRoomRules.translate("What happens when you draw"),
            GameRoomRules.translate("Normally, Space draws one tile. You may start drawing only once in a turn. If a legal play is available afterwards, you can make it; if none is available, your turn ends. Without any playable tile and with an empty boneyard, the game passes automatically. Having drawn is not permission to keep pressing Space for more tiles."),
            GameRoomRules.translate("Allow drawing even when having a playable piece is on by default. Turn it off to require playing a tile you already hold whenever possible. Draw until finding a playable piece is separately off: when enabled, one Space draws a batch ending at the first newly drawn playable tile or an empty boneyard. It is still one drawing action, not many separate turns."),
            GameRoomRules.translate("Forbid drawing in the boneyard turns this into a no-draw game. It disables the other drawing options: you must play a legal tile, or pass automatically if you have none. Undealt tiles remain unavailable. This setting is off by default.")),
          rule_section(:scoring, GameRoomRules.translate("You want as few points as possible"),
            GameRoomRules.translate("The player who empties their hand scores zero. Others add the numbers on their remaining tiles. For instance, 3/5 is worth 8. The 0/0 is a special case: it is worth 10 if it is the only tile left in your hand, but zero if you also have other tiles. If a whole circuit passes with no possible play and no usable draw pile, the round is blocked and everyone counts their remaining hand."),
            GameRoomRules.translate("The score limit defaults to 100 and accepts 1\u2013100000. After the whole round is scored, players reaching or exceeding it are eliminated. The last survivor wins. If everyone crosses the limit together, the lowest score wins; equal lowest scores share the win. Merely timing out several turns does not prove a round blocked if legal moves still exist.")),
          rule_section(:teams, GameRoomRules.translate("Winning together in teams"),
            GameRoomRules.translate("Play in teams is optional. Teams must have equal numbers, at least two players each, and the table must still fit the selected set. Four players form two pairs; six can form two teams of three or three pairs; eight can form two teams of four or four pairs. The shared team setup arranges turns so teams alternate."),
            GameRoomRules.translate("Normally one teammate emptying their hand wins the round for the team. That team scores zero. Every other team adds its own remaining hand values and also the tiles still held by the winning team's partners. If the round blocks, each team counts only its own hands. Count the special 0/0 rule separately in each hand, not across the whole team."),
            GameRoomRules.translate("Whole team finish mode changes this: all teammates must empty their hands before the team ends the round. Players who already finished are skipped and do not draw again. The option is off by default and appears only for team play. Elimination and the final result use team totals.")),
          rule_section(:clock, GameRoomRules.translate("A time limit for each turn"),
            GameRoomRules.translate("Thinking time is zero by default, meaning no limit; a positive value can be up to 600 seconds. At timeout, the game draws one tile if drawing is allowed, the pile is not empty and you have not drawn yet. It then passes without playing the tile. Drawing during your turn does not restart the clock.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: choose a tile."),
            GameRoomRules.translate("Enter: play the selected tile; use the preferred end if both fit."),
            GameRoomRules.translate("G: prefer the left end for subsequent plays."),
            GameRoomRules.translate("D: prefer the right end for subsequent plays."),
            GameRoomRules.translate("Space: draw tiles according to the table rules."),
            GameRoomRules.translate("C: read both ends of the chain."),
            GameRoomRules.translate("V: browse the whole chain."),
            GameRoomRules.translate("E: read hand sizes and the boneyard count."),
            GameRoomRules.translate("Z: next playable tile; automatically play a sole unambiguous move."),
            GameRoomRules.translate("Shift+Z: previous playable tile; automatically play a sole unambiguous move."),
            GameRoomRules.translate("S: read scores."),
            GameRoomRules.translate("T: read whose turn it is."))
        ]
      end
    end
    include GeneratedRulebook
  end
end
