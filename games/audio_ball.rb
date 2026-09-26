# encoding: UTF-8
require_relative 'base'
require_relative '../lib/audio_ball/difficulty'
require_relative '../lib/audio_ball/sound_pack'
require_relative '../lib/realtime/p2p_options'

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class AudioBall < Base
    include PublicHistoryAnnouncements
    include GameRoomRealtime::P2POptions::GameOptions

    POINTS_TO_WIN = 7
    SET_BREAK = 5

    def id; 'audio_ball'; end
    def name; _('Audio Ball'); end
    def supports_bots?; true; end
    def supports_bot_move_delay?; false; end
    def session_runner?; false; end
    def controller_change_phase_error(_replay); nil; end
    def personal_settings_label; _('Audio Ball settings'); end
    def personal_settings_action; :show_audio_ball_settings; end
    def supports_saved_games?; false; end
    def shortcut_features; []; end

    def _(source); GameRoomContent.utf8(super(source)); end
    def participant_name(player); GameRoomContent.utf8(super(player)); end

    def build_client(program, **_services)
      require_relative '../lib/audio_ball/audio'
      require_relative '../lib/audio_ball/client'
      GameRoomAudioBall::Client.new(program, self)
    end

    def audio_tutorial_entries
      [
        ['up', _('Ball sound: Up arrow or W')],
        ['left', _('Ball sound: Left arrow or D')],
        ['down', _('Ball sound: Down arrow or S')],
        ['prepare', _('Preparing the ball: Right arrow or A')],
        ['stop', _('Ball stopped after a successful defence')]
      ].map do |role, label|
        GameRoomAudioTutorial::Entry.new(label: label, asset: GameRoomAudioBall::SoundPack::DEFAULT.fetch(role),
          asset_resolver: ->(program) { GameRoomAudioBall::SoundPack.asset(role, program) })
      end
    end

    def option_definitions
      [
        OptionDefinition.new(key: 'mode', label: _('Game mode'), kind: :choice, default: 'classic',
          choices: [OptionChoice.new(value: 'classic', label: _('Classic'))]),
        OptionDefinition.new(key: 'difficulty', label: _('Difficulty and ball speed'), kind: :choice, default: GameRoomAudioBall::Difficulty::DEFAULT,
          choices: GameRoomAudioBall::Difficulty::PROFILES.each_with_index.map do |profile, i|
            OptionChoice.new(value: i + 1, label: _(profile.fetch(:label)))
          end),
        OptionDefinition.new(key: 'sets_to_win', label: _('Sets to win'), kind: :choice, default: 1,
          choices: [1, 2, 3].map { |count| OptionChoice.new(value: count, label: count.to_s) })
      ] + p2p_option_definitions
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      owner = session['__insertion_user'].to_s
      owner = session['player_one'].to_s if owner.empty?
      owner = players.first.to_s if owner.empty?
      state = { options: options_from_json(session['options']), owner: owner,
        scores: [0, 0], sets: [0, 0], set_number: 1, rally: 0,
        first_server: nil, server: nil, last_point: nil, set_resume_at: nil }
      accepted = []
      history = [starting_history(players)]
      winner = nil
      events.each do |event|
        break if winner
        author = event['__insertion_user'] || repository.actor_of(event, session)
        next unless valid_roster?(players) && same_user?(author, event['__authority_user'] || owner)
        value = event['value']
        next unless value.is_a?(String) && value.length <= 64
        case event['action']
        when 'audio_ball_start'
          next unless state[:first_server] == nil && /\A[01]\z/.match?(value)
          state[:first_server] = value.to_i
          accepted << event
        when 'audio_ball_point'
          match = point_match(value, state[:rally])
          next unless state[:first_server] != nil && match && set_ready?(state, event['created_at'])
          side = match[1].to_i
          state[:scores][side] += 1
          state[:rally] += 1
          state[:set_resume_at] = nil
          state[:last_point] = { winner: side, scores: state[:scores].dup,
            set_number: state[:set_number], set_finished: false, match_finished: false, timeout: match[2] != nil }
          accepted << event
          event_id = repository.event_id(event)
          if match[2]
            history << HistoryEntry.new(key: "timeout:#{event_id}", event_id: event_id, actor: players[1 - side], kind: :move,
              text: _('%{player} did not hit the ball in time. The opponent receives a point.') % { player: participant_name(players[1 - side]) })
          end
          history << HistoryEntry.new(key: "point:#{event_id}", event_id: event_id, actor: players[side], kind: :move,
            text: _('%{player} scores. %{first}: %{one}; %{second}: %{two}.') % {
              player: participant_name(players[side]), first: participant_name(players[0]), one: state[:scores][0],
              second: participant_name(players[1]), two: state[:scores][1] })
          if state[:scores][side] >= POINTS_TO_WIN && state[:scores][side] - state[:scores][1 - side] >= 2
            state[:sets][side] += 1
            state[:last_point][:set_finished] = true
            history << HistoryEntry.new(key: "set:#{event_id}", event_id: event_id, actor: players[side], kind: :set,
              text: _('%{player} wins set %{set}. Sets: %{first}: %{one}; %{second}: %{two}.') % {
                player: participant_name(players[side]), set: state[:set_number], first: participant_name(players[0]),
                one: state[:sets][0], second: participant_name(players[1]), two: state[:sets][1] })
            if state[:sets][side] >= state[:options]['sets_to_win']
              winner = players[side]
              state[:last_point][:match_finished] = true
              history << result_history(event_id: event_id, winner: winner)
            else
              state[:set_number] += 1
              state[:scores] = [0, 0]
              state[:set_resume_at] = event['created_at'].to_i + SET_BREAK if event['created_at']
            end
          end
        end
      end
      state[:server] = (state[:first_server] + state[:rally] / 2) % 2 unless state[:first_server] == nil
      state[:owner] = session['__table_owner'] || owner
      Replay.new(board: nil, players: players, current_player: nil, winner: winner, draw: false,
        accepted_events: accepted, history: history, state: state)
    end

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      return [:invalid, nil] unless valid_roster?(replay.players) && owner_authority?(replay, actor, context)
      return [:invalid, nil] unless selection['kind'] == 'command'
      if selection['action'] == 'audio_ball_start' && replay.state[:first_server] == nil && context.random_source
        first_server = context.random_source.roll(count: 1, sides: 2).values.first - 1
        return [:ok, event_plan('audio_ball_start', first_server)]
      end
      if selection['action'] == 'audio_ball_point' && replay.state[:first_server] != nil
        return [:invalid, nil] unless set_ready?(replay.state, context.now)
        point = selection['point']
        expected = context.local_data&.[]('audio_ball_point')
        return [:ok, event_plan('audio_ball_point', point)] if point == expected && point_match(point, replay.state[:rally])
      end
      [:invalid, nil]
    end

    def automatic_action(replay, actor, context: nil)
      return nil if replay.finished? || !valid_roster?(replay.players) || !owner_authority?(replay, actor, context)
      return { 'kind' => 'command', 'action' => 'audio_ball_start' } if replay.state[:first_server] == nil
      return nil unless set_ready?(replay.state, context.now)
      point = context.local_data&.[]('audio_ball_point')
      return { 'kind' => 'command', 'action' => 'audio_ball_point', 'point' => point } if point_match(point, replay.state[:rally])
      nil
    end

    def automatic_action_due?(replay, actor, context: nil)
      automatic_action(replay, actor, context: context) != nil
    end

    def options_error(_options, player_count: nil)
      _('Audio Ball requires exactly two players.') if player_count != nil && player_count != 2
    end

    def participant_scores(replay)
      scores = replay.state[replay.state[:options]['sets_to_win'] > 1 ? :sets : :scores]
      replay.players.each_with_index.to_h { |player, index| [player, scores[index]] }
    end

    def surface_spec(replay, viewer)
      GameSurfaces::AudioBallSpec.new(game_id: id, header: _('Audio Ball playfield'),
        players: replay.players.map { |player| participant_name(player) }, viewer: player_index(replay.players, viewer),
        scores: replay.state[:scores], sets: replay.state[:sets], set_number: replay.state[:set_number], finished: replay.finished?)
    end

    def custom_game_shortcuts(replay, viewer)
      shortcuts = [
        surface_shortcut(key: 's', modifiers: [:shift], label: _('read points and sets'), command: 'scores'),
        surface_shortcut(key: 't', label: _('read the server and connection status'), command: 'server')
      ]
      if !replay.finished? && player_index(replay.players, viewer) != nil
        shortcuts << surface_shortcut(key: 'w', modifiers: [:control], label: _('hurry the opponent holding the ball'), command: 'hurry')
      end
      shortcuts
    end

    def rule_sections
      # Generated from docs/rulebooks/audio_ball.json; see tools/compile-rulebooks.rb.
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

    private

    def set_ready?(state, now)
      state[:set_resume_at] == nil || now == nil || now.to_f >= state[:set_resume_at]
    end

    def point_match(value, rally)
      /\A#{rally}:([01])(:timeout)?\z/.match(value) if value.is_a?(String) && value.length <= 64
    end

    def valid_roster?(players)
      players.length == 2 && GameRoomParticipants.unique(players).length == 2
    end

    def owner_authority?(replay, actor, context)
      context && same_user?(context.table_owner, replay.state[:owner]) &&
        (same_user?(actor, context.table_owner) || same_user?(actor, replay.players.first))
    end
  end
end
