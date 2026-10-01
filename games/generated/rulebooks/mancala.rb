# Generated from tools/data/rulebooks/mancala.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class Mancala
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:board, GameRoomRules.translate("A board full of seeds"),
            GameRoomRules.translate("Mancala is a family of games about moving seeds between pits. Here two people can play Oware, Ayoayo or Kalah. All three use two rows of six pits and one store for each player. Seeds in your store are your score and never return to play. You want to collect more than your opponent."),
            GameRoomRules.translate("Your row is always at the bottom, from A1 to F1. The opposing row is A2 to F2. Pits in the same column face each other: C1 faces C2, for instance. An observer sees the board from the first player's side. Move announcements use the coordinates shown on your screen."),
            GameRoomRules.translate("Each pit begins with four seeds by default. The table can instead start with any whole number from two to eight in every pit. This changes the total available score: four per pit means 48 seeds altogether. Both players always start equally, and both stores begin empty.")),
          rule_section(:sowing, GameRoomRules.translate("How sowing works"),
            GameRoomRules.translate("On your turn, choose a nonempty pit in your own row and press Enter. Take all its seeds and drop one into each following pit. This is called sowing. Along your bottom row the order is A1 towards F1, then across the opposing row from F2 towards A2 and back to A1. You never sow into your opponent's store."),
            GameRoomRules.translate("For example, sowing four seeds from A1 adds one each to B1, C1, D1 and E1. You do not choose their destinations separately. What happens when the last seed lands depends on the variant, so read the section for the game selected at your table.")),
          rule_section(:oware, GameRoomRules.translate("Oware: capture twos and threes"),
            GameRoomRules.translate("Oware never sows into either store. When a large handful goes all the way around the board, skip the pit you originally emptied. After sowing, capture is possible only if the last seed landed on the opposing side and left exactly two or three seeds in that pit."),
            GameRoomRules.translate("Take those seeds into your store. Then inspect the preceding opposing pit, going backwards along the sowing route: if it also holds two or three, capture it too. Continue until a pit has a different number or you reach your own side. For example, ending beside consecutive opposing pits holding 2, 3 and 2 can capture all three."),
            GameRoomRules.translate("You must not capture every seed left on the opposing side at once. Such a move may be played, but no capture occurs. If the opponent's row is empty before your turn, you must choose a sowing that feeds it when one exists. Otherwise the game ends, and each player keeps the seeds remaining on their own side."),
            GameRoomRules.translate("Oware ends immediately when someone owns more than half of all seeds. With the default 48, that means 25. Power Games also ends a sequence of 120 moves without any capture: each side's remaining seeds go to its own store. This is the local safeguard against endless circulation, not a threefold-repetition rule. Equal final scores mean a draw.")),
          rule_section(:ayoayo, GameRoomRules.translate("Ayoayo: one move can continue through several pits"),
            GameRoomRules.translate("Ayoayo skips the stores and the pit emptied for each sowing. If the last seed lands in a pit that already held seeds, take everything from that pit and continue sowing from there. This continuation is still part of your original move, even on the opposing side. It stops when your last seed lands in an empty pit."),
            GameRoomRules.translate("If that final empty pit is yours and the opposite pit contains seeds, capture all the seeds opposite together with your own last seed. Both pits become empty. For example, three seeds opposite plus your last seed give you four points. Landing on the opposing side or opposite an empty pit gives no capture."),
            GameRoomRules.translate("When the opposing row is empty, you must feed it if a legal move can do so. If the player whose turn comes next has no legal move, all seeds still on the board go to the person who made the last move. This also applies when the next player has seeds but cannot feed the empty opposing row. Power Games uses this particular Ayoayo variant; other published descriptions may award these seeds differently."),
            GameRoomRules.translate("After gathering the remaining seeds, compare the stores. More seeds wins and equal stores mean a draw. Unlike Oware, Ayoayo does not stop merely because someone has passed half of the total.")),
          rule_section(:kalah, GameRoomRules.translate("Kalah: use your store and earn another move"),
            GameRoomRules.translate("In Kalah you sow into your own store as you pass it, immediately scoring that seed. Skip only the opponent's store; on a full circuit your original pit can receive seeds again. Landing the last seed in your store gives you another move. You may earn several extra moves in succession."),
            GameRoomRules.translate("With capturing enabled, ending in your own previously empty pit captures your last seed and every seed in the opposite pit, provided the opposite pit is not empty. Turning off Capture from an empty pit disables this capture only. Sowing into your store and earning extra moves still work."),
            GameRoomRules.translate("The game ends as soon as either row is empty. The other player moves all seeds remaining in their row into their own store. The larger store wins; equal stores mean a draw. There is no requirement to feed an empty opponent in Kalah.")),
          rule_section(:computer, GameRoomRules.translate("Playing against the computer"),
            GameRoomRules.translate("The computer uses the same rules and can see the whole board, just as you can. Calm uses a short search, Steady looks further and is the default, while Sharp considers more continuations and may need longer to answer. These settings change its planning effort, not the number of seeds or scoring."),
            GameRoomRules.translate("Bot delay is a separate setting: zero adds no intentional pause, and values from one to five add that many seconds before the move. It is not a time limit for the search and does not weaken the computer.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Left / Right: move along a row of pits."),
            GameRoomRules.translate("Up / Down: change rows."),
            GameRoomRules.translate("Enter: sow from the selected pit in your own row."),
            GameRoomRules.translate("S: read both stores, highest score first."),
            GameRoomRules.translate("P: read your pits in sowing order."),
            GameRoomRules.translate("Shift+P: read the opposing pits in their sowing order."),
            GameRoomRules.translate("T: read whose turn it is."))
        ]
      end
    end
    include GeneratedRulebook
  end
end
