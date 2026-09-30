# Generated from tools/data/rulebooks/battleship.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class Battleship
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:waters, GameRoomRules.translate("Find the opposing fleet"),
            GameRoomRules.translate("Battleship is a game for two players. Each has a separate board with ten columns, A to J, and ten rows, 1 to 10. Before the first shot, both players secretly arrange their ships. You win by hitting every square occupied by your opponent's ships before they sink all of yours."),
            GameRoomRules.translate("During play you can browse two boards. Enemy waters show the results of your shots, not the unhit ships. Your waters show your own ships and the shots received. The second board is for inspection: Enter there does not fire. Spectators see two boards named after their owners, with public hit and miss information only.")),
          rule_section(:fleet, GameRoomRules.translate("Choose and arrange your ships"),
            GameRoomRules.translate("When a new game starts, each player chooses Randomly or Manually. Randomly places and seals your whole fleet at once, using the selected fleet and the rule about ships touching. Choose Manually if you want to decide where each ship goes: only then does the placement board open. Your choice does not affect how your opponent arranges their fleet."),
            GameRoomRules.translate("The default Polish fleet has ten ships: one covering four squares, two covering three, three covering two, and four covering one. The other fleet has five ships, of lengths 5, 4, 3, 3 and 2. Both players always use the fleet chosen in the table settings."),
            GameRoomRules.translate("A ship must form one straight horizontal or vertical line, without gaps. It cannot bend, run diagonally, overlap another ship or go outside the board. By default, ships must not touch, even at a corner. Enabling Ships may touch removes that spacing restriction, but never allows two ships on the same square."),
            GameRoomRules.translate("To place a ship, press Enter at one end, move to the other end and press Enter again. For a one-square ship, choose the same square twice. For example, A1 followed by A4 places a four-square ship vertically. You can place ships of any available length in any order; the program tells you which lengths remain."),
            GameRoomRules.translate("Backspace cancels a marked first end. If no end is marked, it removes the last ship you placed. An invalid placement leaves the first end selected, so you can choose a different second end or cancel it. After the last ship, confirm that the fleet is ready. Declining takes back that last ship. Once confirmed, the fleet cannot be rearranged.")),
          rule_section(:shots, GameRoomRules.translate("One shot, then your opponent"),
            GameRoomRules.translate("When both fleets are ready, the first player at the table begins. On your turn, choose a square in Enemy waters and press Enter. A miss means there is no ship there. A hit means you struck part of a ship. Hit and sunk means every square of that particular ship has now been hit."),
            GameRoomRules.translate("Every shot ends your turn, including a hit or a sinking. There is no extra shot for hitting a ship in this version. You cannot shoot a square you have already tried. The other player's program answers automatically; neither player needs to type hit or miss."),
            GameRoomRules.translate("With game sounds enabled, you first hear a rocket launch. After that sound finishes, the result is announced with a hit or miss sound. The next move becomes available after that sound ends. You can still browse the board and use chat while listening. Turning game sounds off removes these sound-related pauses."),
            GameRoomRules.translate("Suppose a ship occupies B3, C3 and D3. Hitting B3 and D3 damages it, but it remains afloat until C3 is hit as well. Fleet summaries count surviving squares, not the number of whole ships. A partly damaged ship therefore still contributes its unhit squares.")),
          rule_section(:verification, GameRoomRules.translate("Finishing and playing against the computer"),
            GameRoomRules.translate("When the last ship sinks, both programs reveal their fleets for a final check. The game verifies the original placement and every answer. Only then is the result final. A fleet or answer that disagrees with the original sealed placement makes that player lose; if both fail the check, the result is a draw."),
            GameRoomRules.translate("Until that check, your fleet stays in private local storage. Stay connected so your program can answer shots and reveal it at the end. Saving Battleship for later is currently unavailable: the shared move history alone cannot restore both secret fleets."),
            GameRoomRules.translate("The computer places its own fleet automatically. It chooses shots using the same public answers available to a person, without seeing the opposing fleet. The shared bot-delay setting only adds a pause before its move; it does not change the rules or reveal extra information.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: browse squares."),
            GameRoomRules.translate("Enter: confirm random or manual setup; in manual placement, mark a ship's end; during play, shoot on the enemy board."),
            GameRoomRules.translate("Backspace: cancel the marked end or take back the last ship before sealing."),
            GameRoomRules.translate("Tab / Shift+Tab: move between the game boards and the other screen fields."),
            GameRoomRules.translate("F: read how many squares of your fleet remain afloat."),
            GameRoomRules.translate("Shift+F: read how many enemy fleet squares remain."),
            GameRoomRules.translate("L: read the last answered shot."),
            GameRoomRules.translate("M: read your shots, hits and ships sunk."),
            GameRoomRules.translate("Ctrl+L: browse your shots and their results."),
            GameRoomRules.translate("T: read whose turn it is."))
        ]
      end
    end
    include GeneratedRulebook
  end
end
