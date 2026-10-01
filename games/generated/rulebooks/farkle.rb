# Generated from tools/data/rulebooks/farkle.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class Farkle
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:risk, GameRoomRules.translate("How far do you dare to roll?"),
            GameRoomRules.translate("Farkle is a dice game for two to eight players. You collect points during your turn, then decide whether to save them or risk another roll. Saved points are safe. Points from the turn you are still playing can all disappear in one unlucky roll."),
            GameRoomRules.translate("Start by rolling six dice. Choose a scoring combination from the list and confirm it. Those dice are set aside and their points join your turn total. You can then roll the remaining dice or bank the points if you have reached the required minimum. Banking ends the turn and adds its points to your permanent score."),
            GameRoomRules.translate("If a roll contains no scoring combination, you have farkled: you lose the entire current turn total and play passes on. Your earlier banked score is unaffected. If you manage to score with all six dice, you may roll all six again and continue building the same turn total. This is called hot dice."),
            GameRoomRules.translate("Only dice from the same roll can form a combination. For example, a one saved from an earlier roll cannot be added to two new ones to make a triple. You may combine several scoring groups from the current roll, but every selected die must belong to a valid group. The program does not let you attach a useless die just to get rid of it.")),
          rule_section(:scoring, GameRoomRules.translate("What the dice are worth here"),
            GameRoomRules.translate("A single one is worth 10 points; a single five is worth 5. Other single dice do not score. Three ones give 75. Three twos, threes, fours, fives or sixes give 20, 30, 40, 50 or 60 respectively."),
            GameRoomRules.translate("Four equal dice score 100 plus ten times their value: four twos give 120. Five equal dice score 300 plus twenty times their value: five twos give 340. Six equal dice score 600 plus twenty-five times their value: six twos give 650."),
            GameRoomRules.translate("A run of five consecutive values, 1 to 5 or 2 to 6, gives 100. A run from 1 to 6 gives 200. Three pairs of different values give 150. Two different triples give 250, as do four equal dice together with a pair of another value. That last combination uses six dice; it is not the five-dice full house from Yahtzee."),
            GameRoomRules.translate("When the same selected dice have more than one scoring interpretation, you receive the highest valid value. These are Power Games's values; changing the winning score or banking minimum does not change this scoring table.")),
          rule_section(:banking, GameRoomRules.translate("When you can stop, and when the game ends"),
            GameRoomRules.translate("The first bank has its own minimum, normally 50 points. Until you have a positive saved score, you must collect at least that much in a single turn to bank. Later turns use the ordinary banking minimum, normally 30. Both settings can be changed at the table."),
            GameRoomRules.translate("The winning score defaults to 1000. Reaching it with unbanked points is not enough: you must bank them. Once someone banks enough, the current circuit continues through the last player in seating order. Players who have already played in that circuit do not receive another turn. The highest score then wins; equal highest scores give a draw. Older saved games may retain the earlier immediate-win rule.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: browse scoring combinations, Roll and Bank."),
            GameRoomRules.translate("Enter: perform the selected action."),
            GameRoomRules.translate("D: read the latest roll."),
            GameRoomRules.translate("C: read turn points and the required minimum."),
            GameRoomRules.translate("S: read scores."),
            GameRoomRules.translate("T: read whose turn it is."))
        ]
      end
    end
    include GeneratedRulebook
  end
end
