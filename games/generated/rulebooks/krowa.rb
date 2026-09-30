# Generated from tools/data/rulebooks/krowa.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  module KrowaPresentation
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:goal, GameRoomRules.translate("Reading the clues"),
            GameRoomRules.translate("In Krowa, your task is to guess a Polish noun. At the very beginning, a word is drawn and you are told how many letters it has. You enter guesses with the same number of letters as the secret word. After each attempt, you hear how many letters occupy the same positions in both words. If the answer is kot and you enter sok, you get 1 out of 3: only the middle letter matches. K is not counted because it is the first letter in kot but the third in sok."),
            GameRoomRules.translate("By comparing successive clues, you gradually narrow down the possibilities.")),
          rule_section(:setup, GameRoomRules.translate("Play on your own or with others"),
            GameRoomRules.translate("If you are the table host, you choose the game variant."),
            GameRoomRules.translate("In solo mode, you have two options: Daily Krowa, with a new word each day that is the same for everyone, or Random word, where you can choose the word length. In the latter mode, you have one superpower. You can add words to a dictionary that stores your nouns locally. Hmmm... if you put asdfasdfasdf in there, it will be stored too, but I hope having fun matters more than racking up leaderboard scores. So, if you want to use smerfy as a guess, just press \"Add noun to dictionary and check\". You will not be able to use that word in multiplayer modes, though. Not because I dislike the Smurfs; it is simply not in the database."),
            GameRoomRules.translate("There are also two ways to play with others:"),
            GameRoomRules.translate("Race, where you compete to guess the same word. Depending on the setting, the winner is the person who uses fewer attempts or guesses faster."),
            GameRoomRules.translate("Or Word Tower, a cooperative game. Words are drawn, and everyone takes turns entering guesses while seeing what the other players have entered."),
            GameRoomRules.translate("Daily Krowa is private: nobody can join or observe it. That would make guessing it later far too easy!"),
            GameRoomRules.translate("You can observe all the other modes if the table is public or you are invited to it. If you join Krowa while someone is guessing a random word, you can check the word length and the list and number of their attempts. You can also write in chat: \"p in the fourth position! Seriously, the fourth letter is p!\" But I am not encouraging that.")),
          rule_section(:play, GameRoomRules.translate("How to play"),
            GameRoomRules.translate("Type a noun and press Enter. Each entry disappears from the edit field after submission. A wrong length, a word outside the dictionary, a repeated guess or an attempt made out of turn does not use up an attempt, but does make a funny sound."),
            GameRoomRules.translate("More about the modes:"),
            GameRoomRules.translate("Daily Krowa can draw a word between three and nine letters long. The word is determined using server time, so if you need a different one, you would have to hack into the server and change the date. You can open Daily Krowa only once. If you guess the word, give up or leave the game, it remains unavailable to your account until the next day."),
            GameRoomRules.translate("In Race, everyone guesses independently. You can set the word length or leave it to chance. Either way, you can draw another word, which resets the attempts. You can also set the winning criterion mentioned above:"),
            GameRoomRules.translate("- With time scoring, the shortest time from the start of the word to the submission of the correct answer wins, measured by a clock synchronized with the server;"),
            GameRoomRules.translate("- With attempt scoring, the fewest valid submissions wins. Equal results mean a shared victory."),
            GameRoomRules.translate("In Race, if everyone else has guessed either faster than you or in fewer attempts, the game ends and the word is revealed to you."),
            GameRoomRules.translate("In Word Tower, you take turns, and guessing the word starts another round. Words have 3 to 8 letters, and the shared attempt limit is:"),
            GameRoomRules.translate("Three-letter words: 15 attempts"),
            GameRoomRules.translate("Four-letter words: 24 attempts"),
            GameRoomRules.translate("Five-letter words: 30 attempts"),
            GameRoomRules.translate("Six-letter words: 42 attempts"),
            GameRoomRules.translate("Seven-letter words: 49 attempts"),
            GameRoomRules.translate("Eight-letter words: 64 attempts."),
            GameRoomRules.translate("The tower ends when you run out of attempts or the host gives up. Your score is the number of completed rounds. The round list in the leaderboard contains the words and attempt counts."),
            GameRoomRules.translate("Krowa's music and sound effects are off by default. Ctrl+D opens their switches and separate volume sliders. These sounds also respect the shared game-sound mute and volume settings in Game Room.")),
          rule_section(:gallery, GameRoomRules.translate("Your gallery, dictionary and rankings"),
            GameRoomRules.translate("Daily Krowa has its own entry in Rankings. Choose a date to hear each player's result and number of attempts. Today's solution stays hidden; for previous days, the list also shows the word. After solving Daily Krowa, you can choose whether to publish your result there."),
            GameRoomRules.translate("The gallery remembers the words you have guessed on your own and your best attempt count for each one. You can open it before a game or after it ends. Its menu lets you sort by date, attempt count or word length. Select a word with Enter to open its leaderboard. After a game, you can agree to publish your result, which also opens the leaderboard for that word."),
            GameRoomRules.translate("The Rankings item in the main menu gives you access to word results and Word Tower round counts. Your gallery and custom dictionary are stored locally and separately for each account. To remove your own words, open My dictionary in Krowa settings, select them with Space and choose Delete selected.")),
          rule_section(:saving, GameRoomRules.translate("Saving your game"),
            GameRoomRules.translate("The table creator can save a Race or Word Tower while a word is being guessed, once all submitted attempts have been checked. The local save lets you resume the game with the same players at a new table. Solo games cannot be saved for later.")),
          rule_section(:controls, GameRoomRules.translate("Controls"),
            GameRoomRules.translate("Tab: move to the next field. In table settings, fields unrelated to the selected variant are hidden, so you do not need to skip them."),
            GameRoomRules.translate("Shift+Tab: move to the previous field."),
            GameRoomRules.translate("Enter in the answer field: submit the typed noun and clear the field for the next attempt."),
            GameRoomRules.translate("Ctrl+D: open Krowa settings for music, effects and your custom dictionary."))
        ]
      end
    end
    include GeneratedRulebook
  end
end
