# Generated from tools/data/rulebooks/cat_head_tail.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class CatHeadTail
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:rules, GameRoomRules.translate("Cat, head, tail is a dice game for two to eight players created by TD Programs."),
            GameRoomRules.translate("It is a simple game based on PIG from RS Games containing several differences, which are described below:\nFirst of all, instead of six, the die has eight sides.\n1 loses all points collected so far and ends the turn;\n2 is automatically added to the bank, but the same player may continue playing;\n7 is Head (the cat's head), which does absolutely nothing;\n8 is tail (the cat's tail), which randomly adds or subtracts 8 points.\nThe target score is selected when creating the table; the default is 100.\nAfter the last player's turn in the round ends, the highest score wins. If several players have the same highest score, the game ends in a draw.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: choose an option.\nEnter: confirm the selection.\nS: read scores.\nC: read the number of points in hand.\nT: check whose turn it is."))
        ]
      end
    end
    include GeneratedRulebook
  end
end
