# Generated from tools/data/rulebooks/mexican_train.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class MexicanTrain
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:trains, GameRoomRules.translate("Your train and the trains you share"),
            GameRoomRules.translate("Mexican Train is played by two to eight people with a 91-tile Double 12 set. A central double, called the station, starts every train. In the first round it is 12/12, then 11/11, down to 0/0; if the game continues, the sequence starts again at 12/12. With two to five players, each gets 15 tiles; with six or seven, 12; with eight, 10. The station is removed before dealing and the rest form the boneyard."),
            GameRoomRules.translate("A train is simply a chain of matching dominoes. Everyone has a personal train, initially closed to other players, and there is one shared Mexican train, always open. You may play on your own train, the Mexican train or another player's open train. Match the number at its outer end; an empty train still ends at the station's number. The first starter is chosen at random, and the starting seat then rotates between rounds.")),
          rule_section(:opening, GameRoomRules.translate("Drawing opens a train only when you cannot play"),
            GameRoomRules.translate("Usually you play one tile and your turn ends. If no legal play is available, draw one tile. You may play if a legal move is now available. Otherwise your personal train opens and the turn passes. When the boneyard is empty and you cannot play, the game opens your train and passes automatically instead of asking you to draw from an empty pile."),
            GameRoomRules.translate("Playing on your own train closes it again. Playing on another open train does not close that train, and playing on the Mexican train never closes it. You may choose those other trains even while your own is open; that choice simply leaves yours open for now."),
            GameRoomRules.translate("Allow drawing even when having a playable piece is off by default. Enabling it lets you draw voluntarily before playing. You still get only one draw for the current decision, not repeated draws by pressing Space. After playing a double and gaining another decision, you may draw once again if needed. Drawing does not let you ignore an unfinished double.")),
          rule_section(:doubles, GameRoomRules.translate("Doubles give another play, but leave an obligation"),
            GameRoomRules.translate("Playing a double, such as 9/9, gives you another play. During your own series you may choose any accessible train, and each further double lets you continue. A double left at a train's end is unfinished until a matching tile is put after it. You can close an earlier double in your own series while leaving a later one on another train unfinished."),
            GameRoomRules.translate("Once your turn ends, any unfinished doubles become an obligation for the following players. The most recently left double must be covered first, even if its train is normally somebody else's closed train. Until it is covered, other trains are not legal destinations. If several remain, they are dealt with in reverse order. For example, leaving 5/5 and then 9/9 requires the next player to cover the 9 first. The game announces each newly required double once, not after every pass. Press T to check it again; choosing an illegal train also explains which double you must cover."),
            GameRoomRules.translate("If you cannot cover the required double, draw. If you still cannot, open your own train and pass; the obligation remains for the next player. A non-double play normally ends your turn. There is one important ending exception: if your final hand tile is a double, you win the round immediately without having to cover it.")),
          rule_section(:points, GameRoomRules.translate("Count the tiles left behind"),
            GameRoomRules.translate("The first player with an empty hand wins the round and receives zero points. Everyone else adds the numbers on their remaining tiles. The 0/0 always counts as 10 here, even alongside other tiles. If the boneyard is empty and nobody can make a legal play over a complete circuit, the round is blocked and all players count their hands. Opening a train may create a new legal move, so merely counting passes is not enough to declare a block."),
            GameRoomRules.translate("Fewer points are better. The score limit defaults to 100 and can be 1\u2013100000. Players who reach it are eliminated after the whole round has been scored. The last survivor wins. If everyone would be eliminated together, the lowest total wins, shared if tied. The game is not limited to thirteen rounds: the station cycle repeats as long as the score rules require more play. There are no team or turn-clock variants in this game.")),
          rule_section(:clock, GameRoomRules.translate("When time runs out"),
            GameRoomRules.translate("Thinking time is optional. Zero, the default, means no limit; you may choose 1\u2013600 seconds. When the time expires, you draw one tile if you have not drawn yet and the boneyard is not empty. Your train opens and your turn ends without playing a tile. A double does not restart the clock for your series. Uncovered doubles remain obligations for the following player.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: choose a tile or train."),
            GameRoomRules.translate("Enter: open train choices for the tile, then confirm a train; an unavailable target explains the refusal."),
            GameRoomRules.translate("Escape: cancel train selection and return to the tile."),
            GameRoomRules.translate("Space: draw a tile."),
            GameRoomRules.translate("C: browse trains."),
            GameRoomRules.translate("E: read hand sizes and the boneyard count."),
            GameRoomRules.translate("Z: select the next legally playable tile, without playing it."),
            GameRoomRules.translate("Shift+Z: select the previous legally playable tile, without playing it."),
            GameRoomRules.translate("T: read whose turn it is and any double that must be covered."),
            GameRoomRules.translate("S: read scores."))
        ]
      end
    end
    include GeneratedRulebook
  end
end
