# Generated from tools/data/rulebooks/audio_ball.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class AudioBall
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:court, GameRoomRules.translate("The aim of the game"),
            GameRoomRules.translate("Audio Ball is an audio game played one against one, with another person or a bot. In Classic mode, you catch the opponent's shots and send the ball back. You score a point when the opponent misses. There are three types of shot, each with a distinct sound. Listen to the sound to choose the matching defence."),
            GameRoomRules.translate("Before playing, you can listen to the sounds in the audio tutorial. Open Game rules with Ctrl+F1 and choose Audio tutorial. Browse with the arrow keys, then press Enter or Space to hear the selected sound. The list explains which key goes with each shot, so you can learn the sounds without having to recognise them during a rally."),
            GameRoomRules.translate("The court is 25 steps long. By default, you hear your end on the right and the opponent's end on the left. An incoming ball travels from left to right; your shot travels from right to left. Headphones make it easier to follow the ball. You can reverse this listening perspective in your personal settings.")),
          rule_section(:shots, GameRoomRules.translate("Defending and attacking"),
            GameRoomRules.translate("Up arrow or W corresponds to the first shot type, Left arrow or D to the second, and Down arrow or S to the third. Use the same key to defend against a shot type or to choose it for your own attack."),
            GameRoomRules.translate("After the opponent hits, listen to the ball and press the matching defence key once. You may press it as soon as you recognise the sound, then release it. That choice remains active for this incoming ball, and you catch it automatically within the final two steps of the court. You do not need to time another press at contact. If you choose the wrong direction, you can correct it before the ball passes you. A new press takes priority. When you release it while holding another defence key, the most recently pressed key still held takes over. If you release all keys, the last active defence remains selected."),
            GameRoomRules.translate("Every new ball needs a new press after the opponent's hit, even if the shot type is the same as before. Your previous defence or your own attack does not defend the next ball. If you are still holding a key, release it and press again after the opponent hits. Choosing a defence before that hit does not count."),
            GameRoomRules.translate("A successful defence leaves you holding the ball; it does not return it automatically. Press Right arrow or A to prepare your shot, then make a new press of one of the three shot keys to attack. You may choose any shot type. Prepare in the same way before every serve, including the first serve of the match. Keeping a shot key held down through preparation will not launch the ball."),
            GameRoomRules.translate("Keep focus on the Audio Ball playfield to use the game keys. Typing in chat or using the settings window does not defend, prepare or attack. Return to the playfield when you want to play.")),
          rule_section(:pace, GameRoomRules.translate("Difficulty and time to hit"),
            GameRoomRules.translate("Choose one of five difficulty levels. The times below describe the first full flight across the 25-step court. At every level, each later hit in the rally increases the current speed by 5%."),
            GameRoomRules.translate("Very easy: the first full flight takes 4 seconds. This is a good starting point for learning the three shot sounds and practising their defences."),
            GameRoomRules.translate("Easy: the first full flight takes 2.2 seconds."),
            GameRoomRules.translate("Normal is the default. The first full flight takes 1.5 seconds."),
            GameRoomRules.translate("Hard: the first full flight takes 0.9 seconds."),
            GameRoomRules.translate("Very hard: the first full flight takes 0.6 seconds."),
            GameRoomRules.translate("When playing a bot, difficulty also affects its reaction time and mistakes: higher levels mean faster reactions and fewer wrong defences. The bot follows the same rules for preparing, hitting and defending the ball as a person."),
            GameRoomRules.translate("Each new point starts at the initial speed. The serve does not add a speed increase; acceleration begins with the next hit."),
            GameRoomRules.translate("Before serving or after a defence, you may hold the ball for as long as you like unless the opponent warns you with Ctrl+W. You then have ten seconds to hit. Preparing does not stop or restart the countdown, and repeated warnings do not give you more time. If you fail to hit before time runs out, the opponent scores a point. Only your opponent can issue a warning; observers cannot.")),
          rule_section(:match, GameRoomRules.translate("Serving, scoring and winning"),
            GameRoomRules.translate("The first server is drawn at random once at the start of the match, whether you play a person or a bot. Service then changes after every two completed points. This sequence continues across sets and during play for a two-point lead. A new set does not restart it, and there is no switch to one serve each at deuce."),
            GameRoomRules.translate("To win a set, score at least 7 points and lead by at least two. For example, 7:6 does not end the set, but 8:6 does. If neither player has a two-point lead, keep playing until one does."),
            GameRoomRules.translate("The table's Sets to win setting is 1, 2 or 3; the default is 1. The first player to win the chosen number of sets wins the match. Each new set starts at 0:0, without changing the number of sets already won."),
            GameRoomRules.translate("After a point, the game plays an announcement and reads the score: yours first, then your opponent's. When needed, speech synthesis replaces the recorded score announcement. Observers hear the scores in the order of players at the table."),
            GameRoomRules.translate("There is a short break before the next serve after an ordinary point, and a five-second break between sets. The game automatically announces the set number and who is serving. You do not need to request these announcements."),
            GameRoomRules.translate("Press Shift+S to hear the points and sets won, or T to check who is serving and the connection status. The final set's score remains available after the match. You cannot save an unfinished Audio Ball match to resume later.")),
          rule_section(:personal, GameRoomRules.translate("Listening side and sound packs"),
            GameRoomRules.translate("Press Ctrl+P or choose Audio Ball settings from the table menu before or during a match. Choose Right (default) to hear your end on the right, or Left to hear it on the left. Left reverses the flight and preparation sounds: incoming balls travel from right to left and your attacks from left to right. This affects only what you hear. Your opponent's sound, the controls and the rules stay the same."),
            GameRoomRules.translate("If you have fond memories of the old game Audiodisc, you can bring back its sounds here. Under Ctrl+P, change Sound pack from Default to Sounds from Audiodisc. This replaces the three flight sounds, preparation, stopping the ball after a successful defence and the goal effect. Score recordings stay the same. The audio tutorial uses your selected pack too. The choice is yours alone: other players can use a different pack in the same match."),
            GameRoomRules.translate("Choose Save to keep your listening side and sound pack for future matches on this computer, or Cancel to keep the previous settings. The settings window does not pause the match. A defence chosen before opening it still applies to that ball, but the next ball needs a new press on the playfield.")),
          rule_section(:background, GameRoomRules.translate("Leaving the playfield"),
            GameRoomRules.translate("Opening a menu, help, Messages or another ELTEN window does not pause the match. The ball, bots, score and table chat continue to update. A defence selected before leaving still applies to that incoming ball, but keys used in the other window do not defend or attack. Return to the playfield to choose your next action. The General category of Game Room settings controls speech outside the table window.")),
          rule_section(:controls, GameRoomRules.translate("Keyboard controls"),
            GameRoomRules.translate("Up arrow: choose a defence against the first shot type, or play that shot after preparing."),
            GameRoomRules.translate("W: choose a defence against the first shot type, or play that shot after preparing."),
            GameRoomRules.translate("Left arrow: choose a defence against the second shot type, or play that shot after preparing."),
            GameRoomRules.translate("D: choose a defence against the second shot type, or play that shot after preparing."),
            GameRoomRules.translate("Down arrow: choose a defence against the third shot type, or play that shot after preparing."),
            GameRoomRules.translate("S: choose a defence against the third shot type, or play that shot after preparing."),
            GameRoomRules.translate("Right arrow: prepare a shot while holding the ball before a serve or after a defence."),
            GameRoomRules.translate("A: prepare a shot while holding the ball before a serve or after a defence."),
            GameRoomRules.translate("Shift+S: read the points in the current set and the number of sets won."),
            GameRoomRules.translate("T: check who is serving and the connection status."),
            GameRoomRules.translate("Ctrl+W: warn the opponent holding the ball; they have ten seconds to hit."),
            GameRoomRules.translate("Ctrl+P: choose your listening side and sound pack."))
        ]
      end
    end
    include GeneratedRulebook
  end
end
