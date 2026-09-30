# Generated from tools/data/rulebooks/yahtzee.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class Yahtzee
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:rolls, GameRoomRules.translate("A sheet to fill, not a score to chase forever"),
            GameRoomRules.translate("Two to eight players take turns rolling five dice. On each turn, choose one unused scoring category, such as Fours or Full house, and record your result in it. Each category can be used only once per score sheet."),
            GameRoomRules.translate("Your first roll uses all five dice. You may then reroll any of them, at most twice more. Dice you do not select are kept. After each roll the values are sorted from lowest to highest and all dice begin as kept, so select the ones you want to change. You may stop after the first or second roll; using three rolls is a choice, not a requirement."),
            GameRoomRules.translate("When you stop rolling, choose a category from the scoring list. The list tells you how many points the current dice would give there. A category whose requirement you did not meet is usually worth zero, but you may still sacrifice it to save a more useful row for later.")),
          rule_section(:scores, GameRoomRules.translate("Reading the scoring rows"),
            GameRoomRules.translate("Ones, Twos, Threes, Fours, Fives and Sixes count only dice with that value. For example, 2, 2, 4, 4, 6 gives 4 in Twos, 8 in Fours or 6 in Sixes. Their combined score can earn the bonus described below."),
            GameRoomRules.translate("Three of a kind needs at least three equal dice; Four of a kind needs at least four. Both count all five dice, including the ones outside the matching group. Chance also counts all five, but has no requirement at all."),
            GameRoomRules.translate("Full house needs three equal dice and two of another value. It gives the larger of 25 and the sum of all dice. Thus 6, 6, 6, 4, 4 gives 26, while a lower full house still gives 25. Five equal dice are Yahtzee and give 50 in that row; they are not an ordinary full house."),
            GameRoomRules.translate("Small straight needs four consecutive different values and gives 30; the fifth die may be anything. Large straight needs all five consecutive values and gives 40. Repeated numbers cannot fill a gap: 1, 2, 2, 4, 5 is not a straight."),
            GameRoomRules.translate("Pair, two pairs and misery adds three rows and is enabled by default. Pair needs two equal dice and counts the sum of all five. Two pairs also counts all five but needs pairs of two different values. A full house qualifies; four equal dice alone do not. Misery gives 36 minus the sum of all dice, so a low roll is useful there.")),
          rule_section(:bonuses, GameRoomRules.translate("Three independent bonus settings"),
            GameRoomRules.translate("The 35-point bonus for Ones through Sixes is enabled by default. You earn it when the results in these six categories add up to at least 63 points. You do not need three of each value separately: a strong result in Sixes can compensate for a weak result in Ones. Switching the bonus off leaves the categories themselves unchanged."),
            GameRoomRules.translate("The bonus for additional Yahtzees is enabled by default. First you must have written 50 in the Yahtzee row. Each later five-of-a-kind that you score in another row then adds 100 bonus points. A zero in Yahtzee does not unlock this bonus."),
            GameRoomRules.translate("The Joker rule is a separate checkbox, also enabled by default. It applies to another five-of-a-kind after you have already scored 50 in Yahtzee. First, use the category for the rolled value if it is still available, such as Threes for five threes. If it is already used, choose an unused category outside Ones through Sixes: Full house and either straight are then allowed without their normal pattern. Only when all those other categories are used may you choose another available category from Ones through Sixes. Each category keeps its normal points."),
            GameRoomRules.translate("For example, with 50 in Yahtzee you roll five threes. An unused Threes row takes 15. If Threes is already filled, the Joker may let you put 40 in Large straight instead. The additional 100 is awarded only if its separate bonus setting is on. There is no joker button or physical joker die to use.")),
          rule_section(:sheets, GameRoomRules.translate("Finishing a sheet and a match"),
            GameRoomRules.translate("A sheet takes 13 turns per player, or 16 with the extra rows. Number of matches chooses how many complete sheets everyone plays, from 1 to 10, normally 1. A new sheet starts empty. Scores from all sheets are added, and the highest final total wins; equal highest totals mean a tied result.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Enter: roll or reroll selected dice; with none selected or no rolls left, choose a scoring category."),
            GameRoomRules.translate("Arrows: choose a scoring category."),
            GameRoomRules.translate("Escape: cancel category selection."),
            GameRoomRules.translate("Space: read which dice are kept and which will be rerolled."),
            GameRoomRules.translate("D: read the rolled dice."),
            GameRoomRules.translate("V: open your score sheet."),
            GameRoomRules.translate("Shift+V: open an opponent's score sheet."),
            GameRoomRules.translate("S: read scores."),
            GameRoomRules.translate("T: read whose turn it is."),
            GameRoomRules.translate("1: select one kept die showing 1 for rerolling."),
            GameRoomRules.translate("!: keep one selected die showing 1."),
            GameRoomRules.translate("2: select one kept die showing 2 for rerolling."),
            GameRoomRules.translate("@: keep one selected die showing 2."),
            GameRoomRules.translate("3: select one kept die showing 3 for rerolling."),
            GameRoomRules.translate("#: keep one selected die showing 3."),
            GameRoomRules.translate("4: select one kept die showing 4 for rerolling."),
            GameRoomRules.translate("$: keep one selected die showing 4."),
            GameRoomRules.translate("5: select one kept die showing 5 for rerolling."),
            GameRoomRules.translate("%: keep one selected die showing 5."),
            GameRoomRules.translate("6: select one kept die showing 6 for rerolling."),
            GameRoomRules.translate("^: keep one selected die showing 6."))
        ]
      end
    end
    include GeneratedRulebook
  end
end
