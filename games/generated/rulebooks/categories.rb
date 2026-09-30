# Generated from tools/data/rulebooks/categories.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class Categories
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:sheet, GameRoomRules.translate("One letter, several kinds of answer"),
            GameRoomRules.translate("Countries and cities is played by two to eight people. Each round draws a letter and several categories. Write a word or name beginning with that letter for each category. For example, with B and the categories country, city and animal, you might write Brazil, Berlin and bear. The entries must fit their categories, not merely start with the right letter."),
            GameRoomRules.translate("One participant is the judge for that round and does not write answers or earn points. The others fill in their own sheets. Each field accepts up to 48 characters. You may leave a field empty rather than invent an answer. Submit the sheet when finished; it cannot be changed once submitted. Answers stay hidden while anyone is still writing.")),
          rule_section(:judging, GameRoomRules.translate("A person judges the answers"),
            GameRoomRules.translate("When all sheets are submitted or the answer time ends, writing closes and the answers are revealed. The judge sees identical answers grouped within each category and decides whether they fit the letter, category and meaning. This is not automatic dictionary scoring: discuss doubtful entries with the judge."),
            GameRoomRules.translate("A unique correct answer is worth 2 points. An accepted repeated answer gives each author 1 point, as does an answer judged partially correct. An incorrect or empty answer gives zero. Everyone can see the grades and authors. Once every answer group has been assessed, the judge finishes the review and the round's points are added to the scores.")),
          rule_section(:pools, GameRoomRules.translate("Choose a pool, then draw categories from it"),
            GameRoomRules.translate("Answer language is Polish by default; English is also available. It chooses the alphabet for letter draws and the language you agree to answer in, not the interface language. Category labels follow your interface. Letters do not repeat until the selected alphabet has been used up."),
            GameRoomRules.translate("The Easy pool contains country, city, first name, animal, plant, thing, profession, food and colour. Medium adds surname, famous person, sport, vehicle, clothing, body part, building, musical instrument and book. Hard adds film, song, music group, river, mountain, island, language, invention and chemical element. These names describe the pool, not a different scoring system."),
            GameRoomRules.translate("Custom lets you select your own pool from those 27 categories, and remembers the last custom choice locally. Categories shown in each round chooses how many are drawn from the pool: one to nine, default six. It cannot exceed the size of your pool. For example, choosing all nine Easy categories with six per round still draws only six, and the selection may differ next round.")),
          rule_section(:judge, GameRoomRules.translate("Who judges and how long you write"),
            GameRoomRules.translate("Rotating judge is the default: the role moves around the seating order, so everyone sometimes judges instead of scoring. Table master judges every round makes the creator the permanent judge and removes that person from the scoring competition. With two participants, that setting leaves one answering player and one permanent judge."),
            GameRoomRules.translate("Answer time defaults to 90 seconds. Set zero for unlimited time, or 10\u20133600 seconds. Only writing is timed, not judging. Near the deadline the game warns you; at the deadline it submits the text still in your fields rather than clearing it first. A participant whose answers do not arrive during closing is treated as having empty entries. Without a time limit, all answering players must submit to move on.")),
          rule_section(:finish, GameRoomRules.translate("Equal rounds and tied scores"),
            GameRoomRules.translate("Target score defaults to 100 and can be 10\u20131000. With a rotating judge, reaching it does not stop play at once: finish the current full judge cycle, so everyone has judged equally often. With a permanent judge, the completed scoring round can decide the result. The highest eligible total wins, not necessarily the first person who touched the target."),
            GameRoomRules.translate("A tied lead can give a shared victory or require extra play, the default. In extra play only the tied leaders remain in contention. An outside participant judges if possible; if everyone is tied, judging continues over complete cycles. A permanent judge keeps that role. Further play continues until the tied lead is resolved. This game does not support saving a partly completed match.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Tab: next answer field, submission control or review group."),
            GameRoomRules.translate("Shift+Tab: previous answer field or review group."),
            GameRoomRules.translate("Arrows: during review, select a grade."),
            GameRoomRules.translate("Enter: confirm the selected grade or submission action."),
            GameRoomRules.translate("Ctrl+T: read the remaining answer time, also while typing."),
            GameRoomRules.translate("T: outside answer entry, read the letter and judge."),
            GameRoomRules.translate("S: outside answer entry, read the scores."),
            GameRoomRules.translate("V: outside answer entry, read round information."))
        ]
      end
    end
    include GeneratedRulebook
  end
end
