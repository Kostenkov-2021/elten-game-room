require "digest"
require_relative "base"
require_relative "../lib/tysiac_strategy"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  # Three-player Tysiac and the two-player, two-talon variant.
  # Card identities are reconstructed from the public deal seed, just as in
  # the other card games in Game Room. The interface never announces cards
  # passed by the taker to the other defenders.
  class Tysiac < Base
    RANKS = %w[9 J Q K T A].freeze
    SUITS = %w[H S D C].freeze
    SUIT_NAMES = {
      "C" => _("clubs"),
      "D" => _("diamonds"),
      "H" => _("hearts"),
      "S" => _("spades")
    }.freeze
    RANK_NAMES = {
      "9" => "9",
      "J" => _("jack"),
      "Q" => _("queen"),
      "K" => _("king"),
      "T" => "10",
      "A" => _("ace")
    }.freeze
    CARD_POINTS = {
      "9" => 0,
      "J" => 2,
      "Q" => 3,
      "K" => 4,
      "T" => 10,
      "A" => 11
    }.freeze
    MARRIAGE_POINTS = {
      "H" => 100,
      "D" => 80,
      "C" => 60,
      "S" => 40
    }.freeze
    BID_MINIMUM = 100
    BID_LIMIT_WITHOUT_MARRIAGE = 120
    BID_MAXIMUM = 400
    BID_STEP = 5
    BARREL_DISTANCE = 120
    BARREL_DEALS = 3

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      action = event["action"].to_s
      return "shuffle" if action == "deal"
      return nil if action != "play"

      mode, card = event["value"].to_s.split("|", 2)
      trump = after_replay&.state.to_h[:trump].to_s
      cues = ["play"]
      cues << "draw2" if !trump.empty? && card.to_s.end_with?(trump)
      if mode == "marriage" && history.any? { |entry| entry.kind == :play }
        cues << "1000_mariage"
      end
      cues
    end

    def id
      "tysiac"
    end

    def name
      _("1000 card game")
    end

    def rule_sections
      # Generated from docs/rulebooks/tysiac.json; see tools/compile-rulebooks.rb.
      [
        rule_section(:auction, GameRoomRules.translate("Win the auction, then fulfil your promise"),
          GameRoomRules.translate("The 1000 card game is played individually, by two or three people. Choose the player count when creating the table; the default is three. The deck has 24 cards: nine, jack, queen, king, ten and ace in every suit. Players bid for the right to take a talon. The winning bidder promises to collect at least the contracted number of points during the deal."),
          GameRoomRules.translate("The player after the dealer opens at no less than 100. Later bids rise in steps of five. Passing removes you from this auction, not from the game. You may bid up to 120 plus the values of the marriages you currently hold, with an overall maximum of 400. A marriage is a king and queen of the same suit."),
          GameRoomRules.translate("With three players, each receives seven cards and the three remaining cards form one talon. The auction winner takes those three revealed cards, then gives one card to each opponent in the announced order. Each recipient learns only their own card. Everyone then has eight cards, to be played in eight tricks."),
          GameRoomRules.translate("Once the cards have been given away or set aside, the bidder can raise the final contract within the limit allowed by the marriages still held. Playing the first card accepts the current contract, so a second bid is not compulsory.")),
        rule_section(:two_players, GameRoomRules.translate("Two players: choose one of two talons"),
          GameRoomRules.translate("The two-player variant uses two separate, face-down talons. Choose two or three cards in each talon in the table settings. With two-card talons, each player is dealt ten cards. With three-card talons, each receives nine. Three cards is the default. The auction works as described above."),
          GameRoomRules.translate("The auction winner chooses the first or second talon without seeing either one's contents. Only the chosen talon is then revealed and added to the winner's hand. The other remains face down. The bidder now sets aside as many cards as were taken, one at a time, using Enter on a card. These discards are not shown to the opponent, and no card is passed to them. The players finish with ten cards each for two-card talons, or nine each for three-card talons."),
          GameRoomRules.translate("The checkbox Set-aside cards go to the last trick winner is enabled by default. It awards the card points from both the unchosen talon and the bidder's discards to whoever takes the last trick, before checking the contract. Thus all 120 card points remain in play. It does not award marriages from those cards or add the cards to the winner's hand. If the checkbox is disabled, nobody scores those cards, so fewer than 120 card points may be available in tricks."),
          GameRoomRules.translate("For example, suppose the unchosen talon contains an ace and a nine, and the bidder sets aside a king and a jack. Those four cards are worth 17 points. With the checkbox enabled, winning the last trick gives its winner these 17 points in addition to the points in the trick itself. With it disabled, those 17 points are not awarded.")),
        rule_section(:tricks, GameRoomRules.translate("Taking tricks and declaring marriages"),
          GameRoomRules.translate("The bidder leads the first trick. Everyone plays one card, and the trick's winner leads next. A trick contains two cards with two players, or three cards with three. You must follow the first card's suit if possible. If you have none of that suit, you must use a trump if a trump suit has been established and you hold one. Only otherwise may you discard any card. You do not have to beat a higher card merely because you can."),
          GameRoomRules.translate("The order from strongest to weakest is ace, ten, king, queen, jack, nine. A trump beats every non-trump. With no trump in the trick, the highest card of the led suit wins. At the beginning of the deal there is no trump suit."),
          GameRoomRules.translate("After the first trick, a player leading a trick may declare a marriage by playing its king or queen while still holding the matching partner. The declared suit becomes trump immediately. Hearts add 100 points, diamonds 80, clubs 60 and spades 40. A later marriage changes trump again. Simply owning the pair, or playing it without the declaration, does not award that bonus.")),
        rule_section(:points, GameRoomRules.translate("Points in cards are not the same as the score you receive"),
          GameRoomRules.translate("An ace is worth 11, a ten 10, a king four, a queen three, a jack two and a nine zero. The cards total 120 points. Add any declared marriages before checking the bidder's contract."),
          GameRoomRules.translate("A successful bidder receives exactly the contract value, not all the points collected. A failed bidder loses the contract value. Defenders add their collected points rounded to the nearest five. The bidder's success is checked before rounding: 118 points do not fulfil a contract of 120."),
          GameRoomRules.translate("The target is normally 1000. You can choose another multiple of five, at least 200. Reaching the target ends the game, subject to the barrel rules below. There are no team or alternative-deck settings.")),
        rule_section(:barrel, GameRoomRules.translate("Near the target: the barrel"),
          GameRoomRules.translate("When your score reaches the interval from 120 below the target to just below the target, it is set to exactly 120 below and you go onto the barrel. At the usual target this means 880. Defender points no longer increase your score there. You have three deals to win and fulfil a contract of at least 120."),
          GameRoomRules.translate("Failing a contract on the barrel subtracts its normal value and takes you off. Using up all three chances without success costs 120 and also takes you off. If someone else takes the talon and surrenders before play, that deal does not use one of your chances. You cannot surrender your own contract while on the barrel. A different target moves the barrel threshold with it."),
          GameRoomRules.translate("The game announces when someone goes onto the barrel and records it in the history. S reads scores and marks the players currently on the barrel. Shift+S also tells you how many barrel chances they have left.")),
        rule_section(:penalties, GameRoomRules.translate("Surrendering and collecting no points"),
          GameRoomRules.translate("After seeing the talon but before giving away or setting aside the first card, the bidder may surrender, unless on the barrel. Each defender receives at least 60, or half the contract if that is higher, rounded upwards to five. With two players there is only one defender, receiving the same award. No last-trick award applies to a surrendered deal. The bidder normally receives zero. Every third surrender additionally costs the bidder 120 points."),
          GameRoomRules.translate("Collecting exactly zero unrounded points in three played deals costs 120. A small result that merely rounds to zero does not count as a zero deal. These zeroes are not accumulated while you are on the barrel.")),
        rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
          GameRoomRules.translate("Arrows: choose a bid, talon card or trick card."),
          GameRoomRules.translate("Enter: confirm the current choice; on a card, play or choose a marriage."),
          GameRoomRules.translate("Shift+Enter: declare a legal marriage directly; without one, do not play."),
          GameRoomRules.translate("B: change the final contract before playing the first card."),
          GameRoomRules.translate("H: read your hand."),
          GameRoomRules.translate("C: read the trick cards."),
          GameRoomRules.translate("Ctrl+C: browse the trick cards."),
          GameRoomRules.translate("F: read the trump suit."),
          GameRoomRules.translate("Shift+S: read zeroes, surrenders and barrel chances."),
          GameRoomRules.translate("Z: next legal trick card; a possible marriage prevents automatic play."),
          GameRoomRules.translate("Shift+Z: previous legal trick card; a possible marriage prevents automatic play."),
          GameRoomRules.translate("S: read scores."),
          GameRoomRules.translate("T: read whose turn it is."),
          GameRoomRules.translate("Shift+C: sort by suit or colour; press again to reverse the order."),
          GameRoomRules.translate("Shift+H: sort by rank or value; press again to reverse the order."),
          GameRoomRules.translate("Shift+M: restore the order in which cards were received."))
      ]
    end

    def minimum_players
      2
    end

    def maximum_players
      3
    end

    def supports_bots?
      true
    end

    def bot_strategy
      @bot_strategy ||= TysiacPlanning::Strategy.new
    end

    def perfect_information?
      false
    end

    # A Tysiac bot may inspect its own hand and everything already announced
    # at the table, but never an opponent's hand or an unchosen talon.
    def bot_observation(replay, actor)
      state = replay.state
      player = player_key(state, actor)
      {
        "players" => state[:players],
        "current_player" => state[:current_player],
        "phase" => state[:phase].to_s,
        "round" => state[:round],
        "scores" => state[:scores],
        "barrels" => state[:barrels],
        "bids" => state[:bids],
        "current_bid" => state[:current_bid],
        "current_bidder" => state[:current_bidder],
        "taker" => state[:taker],
        "contract" => state[:contract],
        "hand" => player == nil ? [] : state[:hands].fetch(player, []),
        "talon" => state[:talon_visible] ? state[:talon] : [],
        "discarded_cards" => same_user?(player, state[:taker]) ? state[:discarded_cards].to_a : [],
        "trump" => state[:trump],
        "trick_number" => state[:trick_number],
        "current_trick" => state[:current_trick],
        "round_points" => state[:round_points],
        "tricks_won" => state[:tricks_won],
        "played_cards" => bot_public_played_cards(replay),
        "winner" => state[:winner]
      }
    end

    def bot_action_score(replay, actor, action, context: nil)
      state = replay.state
      return -100_000.0 if state == nil

      case state[:phase]
      when :bidding
        bot_bid_score(state, actor, action, final: false)
      when :passing, :discarding
        if action["action"].to_s == "surrender"
          bot_surrender_score(state, actor)
        else
          bot_pass_card_score(state, actor, action["card"])
        end
      when :contract
        bot_bid_score(state, actor, action, final: true)
      when :playing
        bot_play_score(replay, actor, action)
      else
        -100_000.0
      end
    end

    def option_definitions
      [
        OptionDefinition.new(key: "variant", label: _("1000 card game variant"), kind: :choice, default: "three_players", choices: [
          OptionChoice.new(value: "three_players", label: _("Three players")),
          OptionChoice.new(value: "two_players", label: _("Two players"))
        ]),
        OptionDefinition.new(key: "talon_size", label: _("Cards in each talon"), kind: :choice, default: "3", choices: [
          OptionChoice.new(value: "2", label: _("2 cards")),
          OptionChoice.new(value: "3", label: _("3 cards"))
        ], visible_if: { "variant" => "two_players" }),
        OptionDefinition.new(key: "last_trick_talon", label: _("Set-aside cards go to the last trick winner"),
          kind: :boolean, default: true, visible_if: { "variant" => "two_players" }),
        OptionDefinition.new(
          key: "score_limit",
          label: _("Target score"),
          kind: :integer,
          default: 1_000
        )
      ]
    end

    def options_error(options, player_count: nil)
      values = normalize_options(options)
      target = values["score_limit"].to_i
      return _("The target score must be at least 200 and divisible by 5.") if target < 200 || target % 5 != 0
      required = values["variant"] == "two_players" ? 2 : 3
      if player_count != nil && player_count.to_i != required
        return _("This 1000 card game variant requires exactly %{count} players.") % { count: required }
      end

      nil
    end

    def options_summary(options)
      _("to %{score} points") % { score: normalize_options(options)["score_limit"] }
    end

    def restored_event_value(event, controller_mapping)
      return super if event["action"] != "pass_card"
      target, card = event["value"].split("|", 2)
      "#{controller_mapping.fetch(target.downcase)}|#{card}"
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      state = initial_state(players, options_from_json(session["options"]))
      accepted = []
      history = [starting_history(players)]
      events.each do |event|
        break if state[:winner] != nil

        actor = repository.actor_of(event, session)
        applied = case event["action"].to_s
        when "deal" then apply_deal(state, event, actor, repository, history)
        when "bid" then apply_bid(state, event, actor, repository, history)
        when "pass_card" then apply_pass_card(state, event, actor, repository, history)
        when "take_talon" then apply_take_talon(state, event, actor, repository, history)
        when "discard_card" then apply_discard_card(state, event, actor, repository, history)
        when "contract" then apply_contract(state, event, actor, repository, history)
        when "surrender" then apply_surrender(state, event, actor, repository, history)
        when "play" then apply_play(state, event, actor, repository, history)
        else false
        end
        accepted << event if applied
      end

      Replay.new(
        board: nil,
        players: players,
        current_player: state[:current_player],
        winner: state[:winner],
        draw: false,
        accepted_events: accepted,
        history: history,
        state: state
      )
    end

    def automatic_action(replay, actor, context: nil)
      state = replay.state
      return nil if state == nil || state[:winner] != nil
      return nil if !same_user?(actor, replay.players.first)
      return nil if ![:awaiting_deal, :round_complete].include?(state[:phase])

      { "kind" => "command", "action" => "deal" }
    end

    def active_actors(replay)
      replay.current_player == nil ? [] : [replay.current_player]
    end

    def legal_actions(replay, actor, context: nil)
      state = replay.state
      return [] if state == nil || state[:winner] != nil
      return [] if !same_user?(state[:current_player], actor)

      case state[:phase]
      when :bidding
        legal_bid_values(state, actor).map do |value|
          { "kind" => "command", "action" => "bid", "bid" => value }
        end
      when :choosing_talon
        [0, 1].map { |index| { "kind" => "question", "action" => "submit", "question_id" => "choose_talon", "answer" => index.to_s } }
      when :passing, :discarding
        actions = hand_for(state, actor).map do |card|
          { "kind" => "card", "action" => "select", "card" => card }
        end
        if surrender_available?(state, actor)
          actions << { "kind" => "command", "action" => "surrender" }
        end
        actions
      when :contract
        legal_contract_values(state, actor).map do |value|
          { "kind" => "command", "action" => "contract", "bid" => value }
        end
      when :playing
        legal_cards(state, actor).flat_map do |card|
          result = [{ "kind" => "card", "action" => "select", "card" => "normal|#{card}" }]
          if marriage_available?(state, actor, card)
            result << { "kind" => "card", "action" => "select", "card" => "marriage|#{card}" }
          end
          result
        end
      else
        []
      end
    end

    def playable_card_navigation(replay, viewer)
      state = replay.state
      return nil if state == nil || ![:passing, :discarding, :playing].include?(state[:phase])
      return nil if !same_user?(state[:current_player], viewer)

      actions = legal_actions(replay, viewer).select do |action|
        action["kind"] == "card" && action["action"] == "select"
      end
      grouped = actions.group_by do |action|
        value = action["card"].to_s
        state[:phase] == :playing ? value.split("|", 2).last : value
      end
      card_navigation_spec(
        hand_id: "hand",
        card_actions: grouped,
        automatic_card_ids: grouped.keys
      )
    end

    def action_for(selection, replay, actor, context: nil)
      state = replay.state
      return [:finished, nil] if replay.finished?
      if selection["kind"].to_s == "command" && selection["action"].to_s == "deal"
        return [:not_your_turn, nil] if !same_user?(actor, replay.players.first)
        return [:invalid, nil] if ![:awaiting_deal, :round_complete].include?(state[:phase])
        return [:invalid, nil] if context == nil || context.random_source == nil
        return [:invalid, nil] if options_error(state[:options], player_count: state[:players].length)

        round = state[:round].to_i + 1
        count = state[:players].length
        dealer = state[:dealer_index] == nil ? nil : (state[:dealer_index].to_i + 1) % count
        seed = random_seed(context.random_source)
        dealer = seed.to_i(16) % count if dealer == nil
        return [:ok, event_plan("deal", [round, dealer, seed].join("|"))]
      end

      return [:not_your_turn, nil] if !same_user?(state[:current_player], actor)
      action = selection["action"].to_s
      if selection["choice_id"].to_s == "marriage" && state[:phase] != :playing
        return [:marriage_not_available, nil]
      end
      if selection["kind"].to_s == "command" && action == "contract"
        return [:invalid, nil] if !contract_open?(state, actor)
        value = Integer(selection["bid"].to_s, 10)
        return [:invalid_bid, nil] if !legal_contract_values(state, actor).include?(value)
        return [:ok, event_plan("contract", value)]
      end
      case state[:phase]
      when :bidding
        bidding_selection = selection["kind"].to_s == "command" && action == "bid"
        question_selection = selection["kind"].to_s == "question" && action == "submit" &&
          selection["question_id"].to_s == "auction_bid"
        hand_selection = selection["kind"].to_s == "card" && action == "select" &&
          selection["zone"].to_s == "hand"
        return [:invalid, nil] if !bidding_selection && !question_selection && !hand_selection
        value = if question_selection
          selection["answer"]
        elsif hand_selection
          selection["card"]
        else
          selection["bid"]
        end.to_s
        value = Integer(value, 10) if value != "pass"
        return [:invalid_bid, nil] if !legal_bid_values(state, actor).map(&:to_s).include?(value.to_s)
        [:ok, event_plan("bid", value)]
      when :choosing_talon
        return [:invalid, nil] unless selection["kind"].to_s == "question" && action == "submit" && selection["question_id"].to_s == "choose_talon"
        return [:invalid, nil] unless %w[0 1].include?(selection["answer"].to_s)
        [:ok, event_plan("take_talon", selection["answer"])]
      when :passing, :discarding
        if selection["kind"].to_s == "command" && action == "surrender"
          return [:cannot_surrender, nil] if !surrender_available?(state, actor)
          return [:ok, event_plan("surrender", "")]
        end
        return [:invalid, nil] if selection["kind"].to_s != "card" || action != "select"
        card = selection["card"].to_s
        return [:card_not_in_hand, nil] if !hand_for(state, actor).include?(card)
        return [:ok, event_plan("discard_card", card)] if state[:phase] == :discarding
        target = pass_recipients(state)[state[:pass_index].to_i]
        return [:invalid, nil] if target == nil
        [:ok, event_plan("pass_card", "#{target}|#{card}")]
      when :contract
        if selection["kind"].to_s == "card" && action == "select"
          card = selection["card"].to_s
          return [:card_not_in_hand, nil] if !hand_for(state, actor).include?(card)
          return [
            :ok,
            ActionPlan.new(events: [
              EventCommand.new(action: "contract", value: state[:contract].to_i.to_s),
              EventCommand.new(action: "play", value: "normal|#{card}")
            ])
          ]
        end
        [:invalid, nil]
      when :playing
        return [:invalid, nil] if selection["kind"].to_s != "card" || action != "select"
        mode, card = parse_play(selection["card"])
        return [:card_not_in_hand, nil] if !hand_for(state, actor).include?(card)
        return [:must_follow_suit, nil] if !legal_cards(state, actor).include?(card)
        return [:marriage_not_available, nil] if selection["choice_id"].to_s == "marriage" && mode == "normal"
        return [:marriage_not_available, nil] if mode == "marriage" && !marriage_available?(state, actor, card)
        return [:invalid, nil] if mode != "normal" && mode != "marriage"
        [:ok, event_plan("play", "#{mode}|#{card}")]
      else
        [:invalid, nil]
      end
    rescue ArgumentError
      [:invalid, nil]
    end

    def hand_sorting_available?(replay, viewer)
      !hand_for(replay.state, viewer).to_a.empty?
    end

    def surface_spec(replay, viewer)
      state = replay.state
      if state[:phase] == :choosing_talon && same_user?(state[:taker], viewer)
        return GameSurfaces::QuestionSpec.new(
          id: "choose_talon", prompt: _("Choose a talon"), mode: :single_choice,
          options: [
            GameSurfaces::QuestionOption.new(id: "0", label: _("First talon"), value: "0"),
            GameSurfaces::QuestionOption.new(id: "1", label: _("Second talon"), value: "1")
          ], value: "0", required: true, submit_on_select: true
        )
      end
      hand_cards = hand_for(state, viewer).sort_by { |card| card_sort_key(card) }.map do |card|
        item = surface_card(state, viewer, card)
        item.sort_keys = standard_hand_sort_keys(rank: card_rank(card), suit: card_suit(card), position: hand_for(state, viewer).index(card))
        item
      end
      cards = GameSurfaces::CardTableSpec.new(zones: [
        GameSurfaces::CardZoneSpec.new(
          id: "hand",
          header: hand_header(state, viewer),
          cards: hand_cards,
          hand_order: hand_for(state, viewer).dup, hand_epoch: [viewer, state[:round]].join(":"),
          empty_label: _("Your hand is empty")
        )
      ])
      command = surrender_command(state, viewer)
      return cards if command == nil

      GameSurfaces::CompositeSpec.new(
        parts: [
          GameSurfaces::SurfacePart.new(id: "cards", surface: cards),
          GameSurfaces::SurfacePart.new(id: "actions", surface: command)
        ]
      )
    end

    def participant_scores(replay)
      replay.state[:scores].dup
    end

    def shortcut_features
      super + [:hand, :table_cards, :table_cards_list, :led_suit, :scores, :statistics, :bidding]
    end

    def shortcut_feature_data(feature, replay, viewer)
      state = replay.state
      case feature.to_sym
      when :hand
        { message: hand_text(state, viewer) }
      when :table_cards
        { message: table_cards_text(state) }
      when :table_cards_list
        table_cards_browse_data(state)
      when :led_suit
        {
          label: _("read the trump suit"),
          message: state[:trump] == nil ? _("There is no trump suit.") : _("Trump: %{suit}.") % { suit: SUIT_NAMES.fetch(state[:trump]) }
        }
      when :scores
        { message: scores_text(state, sorted: true) }
      when :statistics
        { message: statistics_text(state) }
      when :bidding
        if contract_open?(state, viewer)
          bid_choice_data(state, viewer, final: true)
        else
          { message: bids_text(state) }
        end
      else
        super
      end
    end

    def move_error(status)
      case status
      when :invalid_bid
        _("Choose one of the available bids.")
      when :card_not_in_hand
        _("This card is not in your hand.")
      when :must_follow_suit
        _("You must follow suit or play a trump when required.")
      when :marriage_not_available
        _("This marriage cannot be declared now.")
      when :cannot_surrender
        _("You cannot surrender this deal now.")
      else
        super
      end
    end

    def history_entries_for_display(replay, viewer, surface_state: {})
      replay.history.map do |entry|
        next entry if ![:pass_card, :discard_card].include?(entry.kind)

        displayed = entry.dup
        displayed.text = if entry.kind == :discard_card
          same_user?(entry.actor, viewer) ? _("You set aside %{card}.") % { card: card_label(entry.value) } : entry.text
        else
          passed_card_text(entry.actor, entry.field, entry.value, viewer)
        end
        displayed
      end
    end

    def describe_event(event, repository, replay, viewer)
      event_id = repository.event_id(event)
      entries = history_entries_for_display(replay, viewer).select do |entry|
        entry.event_id.to_i == event_id.to_i
      end
      messages = entries.map(&:text)
      if event["action"].to_s == "pass_card" && same_user?(repository.actor_of(event), viewer)
        target, card = event["value"].to_s.split("|", 2)
        if target != nil && card != nil
          recipients = replay.players.reject do |player|
            same_user?(player, repository.actor_of(event))
          end
          target_index = recipients.index { |player| same_user?(player, target) }
          next_target = target_index == nil ? nil : recipients[target_index + 1]
          if next_target != nil
            messages << _("Choose a card to give to %{player}.") % {
              player: participant_name(next_target)
            }
          end
          return messages
        end
      end
      messages.empty? ? nil : messages
    end

    def turn_announcement(replay, viewer)
      prompt = passing_prompt(replay.state, viewer)
      return prompt if prompt != nil
      if replay.state[:phase] == :choosing_talon && same_user?(replay.current_player, viewer)
        return _("Choose a talon.")
      end

      super
    end

    private

    def initial_state(players, options)
      {
        players: players,
        options: options,
        scores: players.each_with_object({}) { |player, result| result[player] = 0 },
        barrels: players.each_with_object({}) do |player, result|
          result[player] = { active: false, deals_left: 0 }
        end,
        zero_rounds: players.each_with_object({}) { |player, result| result[player] = 0 },
        surrender_uses: players.each_with_object({}) { |player, result| result[player] = 0 },
        round: 0,
        dealer_index: nil,
        phase: :awaiting_deal,
        current_player: nil,
        hands: players.each_with_object({}) { |player, result| result[player] = [] },
        talon: [],
        talons: [],
        set_aside: [],
        discarded_cards: [],
        talon_visible: false,
        bids: players.each_with_object({}) { |player, result| result[player] = nil },
        passed: players.each_with_object({}) { |player, result| result[player] = false },
        current_bid: nil,
        current_bidder: nil,
        first_bidder: nil,
        taker: nil,
        contract: nil,
        pass_index: 0,
        current_trick: [],
        trick_number: 0,
        trump: nil,
        round_points: players.each_with_object({}) { |player, result| result[player] = 0 },
        tricks_won: players.each_with_object({}) { |player, result| result[player] = 0 },
        winner: nil
      }
    end

    def apply_deal(state, event, actor, repository, history)
      return false if options_error(state[:options], player_count: state[:players].length)
      return false if !same_user?(actor, state[:players].first)
      return false if ![:awaiting_deal, :round_complete].include?(state[:phase])
      round, dealer, seed = parse_deal(event["value"])
      return false if round != state[:round].to_i + 1
      count = state[:players].length
      return false if !dealer.between?(0, count - 1)
      if state[:dealer_index] != nil
        return false if dealer != (state[:dealer_index].to_i + 1) % count
      end

      deck = shuffled_deck(seed)
      hands = {}
      hand_size = two_players?(state) ? 12 - talon_size(state) : 7
      state[:players].each_with_index do |player, index|
        hands[player] = deck.slice(index * hand_size, hand_size)
      end
      state[:round] = round
      state[:dealer_index] = dealer
      state[:phase] = :bidding
      state[:hands] = hands
      state[:talon] = two_players?(state) ? [] : deck.last(3)
      state[:talons] = two_players?(state) ? deck.last(talon_size(state) * 2).each_slice(talon_size(state)).to_a : []
      state[:set_aside] = []
      state[:discarded_cards] = []
      state[:talon_visible] = false
      state[:bids] = state[:players].each_with_object({}) { |player, result| result[player] = nil }
      state[:passed] = state[:players].each_with_object({}) { |player, result| result[player] = false }
      state[:current_bid] = nil
      state[:current_bidder] = nil
      state[:first_bidder] = state[:players][(dealer + 1) % count]
      state[:current_player] = state[:first_bidder]
      state[:taker] = nil
      state[:contract] = nil
      state[:pass_index] = 0
      state[:current_trick] = []
      state[:trick_number] = 0
      state[:trump] = nil
      state[:round_points] = state[:players].each_with_object({}) { |player, result| result[player] = 0 }
      state[:tricks_won] = state[:players].each_with_object({}) { |player, result| result[player] = 0 }
      event_id = repository.event_id(event)
      history << HistoryEntry.new(
        key: "deal:#{round}",
        text: _("Round %{round} was dealt by %{dealer}. %{player} opens the auction.") % {
          round: round,
          dealer: participant_name(state[:players][dealer]),
          player: participant_name(state[:first_bidder])
        },
        event_id: event_id,
        actor: actor,
        kind: :deal
      )
      true
    rescue ArgumentError
      false
    end

    def apply_bid(state, event, actor, repository, history)
      return false if state[:phase] != :bidding || !same_user?(state[:current_player], actor)
      value = event["value"].to_s
      parsed = value == "pass" ? "pass" : Integer(value, 10)
      return false if !legal_bid_values(state, actor).map(&:to_s).include?(parsed.to_s)

      player = player_key(state, actor)
      event_id = repository.event_id(event)
      if parsed == "pass"
        state[:passed][player] = true
        state[:bids][player] = "pass"
        history << HistoryEntry.new(
          key: "bid:#{event_id}",
          text: _("%{player} passed.") % { player: participant_name(player) },
          event_id: event_id,
          actor: player,
          kind: :bid
        )
      else
        state[:current_bid] = parsed
        state[:current_bidder] = player
        state[:bids][player] = parsed
        history << HistoryEntry.new(
          key: "bid:#{event_id}",
          text: _("%{player} bid %{bid}.") % { player: participant_name(player), bid: parsed },
          event_id: event_id,
          actor: player,
          kind: :bid
        )
      end

      active = state[:players].reject { |candidate| state[:passed][candidate] }
      if active.length == 1 && state[:current_bidder] != nil
        finish_bidding(state, event_id, history)
      else
        state[:current_player] = next_bidding_player(state, player)
      end
      true
    rescue ArgumentError
      false
    end

    def finish_bidding(state, event_id, history)
      state[:taker] = state[:current_bidder]
      state[:contract] = state[:current_bid]
      if two_players?(state)
        state[:phase] = :choosing_talon
      else
        state[:hands][state[:taker]].concat(state[:talon])
        state[:talon_visible] = true
        state[:phase] = :passing
      end
      state[:current_player] = state[:taker]
      state[:pass_index] = 0
      history << HistoryEntry.new(
        key: "auction_won:#{event_id}",
        text: _("%{player} won the auction at %{bid}.") % {
          player: participant_name(state[:taker]),
          bid: state[:contract]
        },
        event_id: event_id,
        actor: state[:taker],
        kind: :auction_won
      )
      reveal_talon(state, event_id, history) unless two_players?(state)
    end

    def reveal_talon(state, event_id, history)
      history << HistoryEntry.new(
        key: "talon:#{event_id}",
        text: _("The talon is %{cards}.") % {
          cards: state[:talon].map { |card| card_label(card) }.join(", ")
        },
        event_id: event_id,
        actor: state[:taker],
        kind: :talon
      )
    end

    def apply_take_talon(state, event, actor, repository, history)
      return false unless state[:phase] == :choosing_talon && same_user?(state[:taker], actor)
      return false unless %w[0 1].include?(event["value"].to_s)
      index = event["value"].to_i
      state[:talon] = state[:talons].fetch(index).dup
      state[:set_aside] = state[:talons].fetch(1 - index).dup
      state[:hands][state[:taker]].concat(state[:talon])
      state[:talon_visible] = true
      state[:phase] = :discarding
      event_id = repository.event_id(event)
      history << HistoryEntry.new(key: "take_talon:#{event_id}",
        text: _("%{player} chose talon %{number}.") % { player: participant_name(state[:taker]), number: index + 1 },
        event_id: event_id, actor: state[:taker], kind: :take_talon)
      reveal_talon(state, event_id, history)
      true
    end

    def apply_discard_card(state, event, actor, repository, history)
      return false unless state[:phase] == :discarding && same_user?(state[:taker], actor)
      card = event["value"].to_s
      hand = state[:hands][state[:taker]]
      return false unless hand.include?(card)
      hand.delete_at(hand.index(card))
      state[:set_aside] << card
      state[:discarded_cards] << card
      state[:pass_index] += 1
      event_id = repository.event_id(event)
      history << HistoryEntry.new(key: "discard:#{event_id}",
        text: _("%{player} set aside a card.") % { player: participant_name(state[:taker]) },
        event_id: event_id, actor: state[:taker], kind: :discard_card, value: card)
      state[:phase] = :contract if state[:pass_index] == talon_size(state)
      true
    end

    def apply_pass_card(state, event, actor, repository, history)
      return false if state[:phase] != :passing || !same_user?(state[:taker], actor)
      target, card = event["value"].to_s.split("|", 2)
      expected = pass_recipients(state)[state[:pass_index].to_i]
      return false if expected == nil || !same_user?(expected, target)
      taker = state[:taker]
      return false if !state[:hands][taker].include?(card)

      state[:hands][taker].delete_at(state[:hands][taker].index(card))
      state[:hands][expected] << card
      state[:pass_index] += 1
      event_id = repository.event_id(event)
      history << HistoryEntry.new(
        key: "pass:#{event_id}",
        text: _("%{taker} gave a card to %{player}.") % {
          taker: participant_name(taker),
          player: participant_name(expected)
        },
        event_id: event_id,
        actor: taker,
        kind: :pass_card,
        field: expected,
        value: card
      )
      if state[:pass_index] >= 2
        state[:phase] = :contract
        state[:current_player] = taker
      end
      true
    end

    def apply_contract(state, event, actor, repository, history)
      return false if !contract_open?(state, actor)
      value = Integer(event["value"].to_s, 10)
      return false if !legal_contract_values(state, actor).include?(value)

      state[:contract] = value
      state[:phase] = :playing
      state[:current_player] = state[:taker]
      state[:talon_visible] = false
      event_id = repository.event_id(event)
      history << HistoryEntry.new(
        key: "contract:#{event_id}",
        text: _("%{player} set the contract at %{contract}.") % {
          player: participant_name(state[:taker]),
          contract: value
        },
        event_id: event_id,
        actor: state[:taker],
        kind: :contract
      )
      true
    rescue ArgumentError
      false
    end

    def apply_surrender(state, event, actor, repository, history)
      return false if !surrender_available?(state, actor)
      event_id = repository.event_id(event)
      history << HistoryEntry.new(
        key: "surrender:#{event_id}",
        text: _("%{player} surrendered the deal at a contract of %{contract}.") % {
          player: participant_name(state[:taker]),
          contract: state[:contract]
        },
        event_id: event_id,
        actor: state[:taker],
        kind: :surrender
      )
      complete_round(state, event_id, history, surrendered: true)
      true
    end

    def apply_play(state, event, actor, repository, history)
      return false if state[:phase] != :playing || !same_user?(state[:current_player], actor)
      begin
        mode, card = parse_play(event["value"])
      rescue ArgumentError
        return false
      end
      player = player_key(state, actor)
      return false if !state[:hands][player].include?(card)
      return false if !legal_cards(state, player).include?(card)
      return false if mode == "marriage" && !marriage_available?(state, player, card)
      return false if mode != "normal" && mode != "marriage"

      state[:hands][player].delete_at(state[:hands][player].index(card))
      event_id = repository.event_id(event)
      text = _("%{player} played %{card}.") % {
        player: participant_name(player),
        card: card_label(card)
      }
      if mode == "marriage"
        suit = card_suit(card)
        bonus = MARRIAGE_POINTS.fetch(suit)
        state[:round_points][player] += bonus
        state[:trump] = suit
        text = _("%{player} declared the %{suit} marriage for %{points} points by playing %{card}. %{suit} is now trump.") % {
          player: participant_name(player),
          suit: SUIT_NAMES.fetch(suit),
          points: bonus,
          card: card_label(card)
        }
      end
      state[:current_trick] << { player: player, card: card }
      history << HistoryEntry.new(
        key: "play:#{event_id}",
        text: text,
        event_id: event_id,
        actor: player,
        kind: :play
      )

      if state[:current_trick].length < state[:players].length
        state[:current_player] = next_player(state, player)
        return true
      end

      winner = trick_winner(state[:current_trick], state[:trump])
      points = state[:current_trick].sum { |play| CARD_POINTS.fetch(card_rank(play[:card])) }
      state[:round_points][winner] += points
      state[:tricks_won][winner] += 1
      history << HistoryEntry.new(
        key: "trick:#{event_id}",
        text: _("%{player} won the trick for %{points} card points.") % {
          player: participant_name(winner),
          points: points
        },
        event_id: event_id,
        actor: winner,
        kind: :trick
      )
      state[:current_trick] = []
      state[:trick_number] += 1
      if state[:hands].values.all?(&:empty?)
        if two_players?(state) && state[:options]["last_trick_talon"]
          extra = state[:set_aside].sum { |card| CARD_POINTS.fetch(card_rank(card)) }
          state[:round_points][winner] += extra
          history << HistoryEntry.new(key: "set_aside:#{event_id}",
            text: _("%{player} receives %{points} points from the set-aside cards for winning the last trick.") % {
              player: participant_name(winner), points: extra
            }, event_id: event_id, actor: winner, kind: :set_aside, value: extra)
        end
        complete_round(state, event_id, history, surrendered: false)
      else
        state[:current_player] = winner
      end
      true
    rescue KeyError
      false
    end

    def complete_round(state, event_id, history, surrendered:)
      before_scores = state[:scores].dup
      before_zero_rounds = state[:zero_rounds].dup
      before_surrender_uses = state[:surrender_uses].dup
      barrel_before = state[:players].each_with_object({}) do |player, result|
        barrel = state[:barrels][player]
        result[player] = { active: barrel[:active], deals_left: barrel[:deals_left] }
      end
      if surrendered
        apply_surrender_scores(state, barrel_before)
      else
        apply_played_scores(state, barrel_before)
        apply_zero_penalties(state, barrel_before)
      end
      settle_barrels_and_winner(state, barrel_before, consume_deal: !surrendered)

      round_results = state[:players].map do |player|
        delta = state[:scores][player].to_i - before_scores[player].to_i
        round_score_text(player, state[:round_points][player].to_i, delta)
      end
      notices = if surrendered
        taker = state[:taker]
        [cycle_notice(taker, before_surrender_uses[taker].to_i + 1, :surrender)]
      else
        state[:players].filter_map do |player|
          next if barrel_before[player][:active] || state[:round_points][player].to_i != 0

          cycle_notice(player, before_zero_rounds[player].to_i + 1, :zero)
        end
      end
      (round_results + notices).each_with_index do |text, index|
        history << HistoryEntry.new(
          key: "round:#{state[:round]}:#{event_id}:#{index}",
          text: text,
          event_id: event_id,
          actor: state[:taker],
          kind: :round_result
        )
      end
      state[:players].each do |player|
        next if barrel_before[player][:active] || !state[:barrels][player][:active]
        history << HistoryEntry.new(
          key: "barrel:#{state[:round]}:#{event_id}:#{player}",
          text: _("%{player} is now on the barrel.") % { player: participant_name(player) },
          event_id: event_id, actor: player, kind: :barrel
        )
      end
      if state[:winner] != nil
        state[:phase] = :finished
        state[:current_player] = nil
        history << result_history(event_id: event_id, winner: state[:winner])
      else
        state[:phase] = :round_complete
        state[:current_player] = nil
        state[:talon_visible] = false
      end
    end

    def apply_played_scores(state, barrel_before)
      taker = state[:taker]
      made = state[:round_points][taker].to_i >= state[:contract].to_i
      state[:players].each do |player|
        on_barrel = barrel_before[player][:active]
        if same_user?(player, taker)
          if on_barrel
            if made && state[:contract].to_i >= BARREL_DISTANCE
              state[:scores][player] += state[:contract].to_i
            elsif !made
              state[:scores][player] -= state[:contract].to_i
              leave_barrel(state, player)
            end
          else
            state[:scores][player] += made ? state[:contract].to_i : -state[:contract].to_i
          end
        elsif !on_barrel
          state[:scores][player] += round_nearest_five(state[:round_points][player])
        end
      end
    end

    def apply_surrender_scores(state, barrel_before)
      taker = state[:taker]
      state[:surrender_uses][taker] += 1
      if state[:surrender_uses][taker] >= 3
        state[:scores][taker] -= BARREL_DISTANCE
        state[:surrender_uses][taker] = 0
      end
      award = round_up_five([60, state[:contract].to_f / 2.0].max)
      state[:players].each do |player|
        next if same_user?(player, taker) || barrel_before[player][:active]
        state[:scores][player] += award
      end
    end

    def apply_zero_penalties(state, barrel_before)
      state[:players].each do |player|
        next if barrel_before[player][:active]
        if state[:round_points][player].to_i == 0
          state[:zero_rounds][player] += 1
          if state[:zero_rounds][player] >= 3
            state[:scores][player] -= BARREL_DISTANCE
            state[:zero_rounds][player] = 0
          end
        end
      end
    end

    def settle_barrels_and_winner(state, barrel_before, consume_deal: true)
      target = state[:options]["score_limit"].to_i
      if consume_deal
        state[:players].each do |player|
          next if !barrel_before[player][:active] || !state[:barrels][player][:active]
          next if state[:scores][player] >= target

          state[:barrels][player][:deals_left] -= 1
          if state[:barrels][player][:deals_left] <= 0
            state[:scores][player] -= BARREL_DISTANCE
            leave_barrel(state, player)
          end
        end
      end

      winners = state[:players].select { |player| state[:scores][player] >= target }
      if !winners.empty?
        state[:winner] = winners.max_by { |player| state[:scores][player] }
        return
      end

      state[:players].each do |player|
        next if state[:barrels][player][:active]
        if state[:scores][player] >= target - BARREL_DISTANCE && state[:scores][player] < target
          state[:scores][player] = target - BARREL_DISTANCE
          state[:barrels][player][:active] = true
          state[:barrels][player][:deals_left] = BARREL_DEALS
        end
      end
    end

    def leave_barrel(state, player)
      state[:barrels][player][:active] = false
      state[:barrels][player][:deals_left] = 0
    end

    def legal_bid_values(state, actor)
      player = player_key(state, actor)
      return [] if player == nil || state[:passed][player]
      minimum = state[:current_bid] == nil ? BID_MINIMUM : state[:current_bid].to_i + BID_STEP
      maximum = maximum_bid_for_hand(state[:hands][player])
      values = (minimum..maximum).step(BID_STEP).to_a
      can_pass = state[:current_bid] != nil && !same_user?(player, state[:first_bidder])
      can_pass = state[:current_bid] != nil if state[:bids][player] != nil
      can_pass ? ["pass"] + values : values
    end

    def contract_open?(state, actor)
      [:contract, :playing].include?(state[:phase]) &&
        same_user?(state[:taker], actor) && same_user?(state[:current_player], actor) &&
        state[:trick_number].to_i == 0 && state[:current_trick].empty?
    end

    def legal_contract_values(state, actor)
      return [] if !same_user?(state[:taker], actor)
      maximum = maximum_bid_for_hand(hand_for(state, actor))
      maximum = [maximum, state[:contract].to_i].max
      (state[:contract].to_i..maximum).step(BID_STEP).to_a
    end

    def next_bidding_player(state, actor)
      index = state[:players].index { |player| same_user?(player, actor) }
      state[:players].length.times do
        index = (index + 1) % state[:players].length
        return state[:players][index] if !state[:passed][state[:players][index]]
      end
      nil
    end

    def next_player(state, actor)
      index = state[:players].index { |player| same_user?(player, actor) }
      state[:players][(index + 1) % state[:players].length]
    end

    def pass_recipients(state)
      state[:players].reject { |player| same_user?(player, state[:taker]) }
    end

    def surrender_available?(state, actor)
      [:passing, :discarding].include?(state[:phase]) && state[:pass_index].to_i == 0 &&
        same_user?(state[:taker], actor) && !state[:barrels][state[:taker]][:active]
    end

    def bot_bid_score(state, actor, action, final:)
      value = action["bid"]
      target = bot_contract_target(state, actor)
      if value.to_s == "pass"
        next_bid = state[:current_bid] == nil ? BID_MINIMUM : state[:current_bid].to_i + BID_STEP
        return target < next_bid ? 20_000.0 : -20_000.0
      end

      bid = Integer(value.to_s, 10)
      if bid <= target
        # The highest declaration still supported by the hand wins. This also
        # keeps the current contract when the post-talon estimate has fallen.
        10_000.0 + bid
      else
        # An opening player may be forced to say 100. Prefer the smallest
        # unavoidable overbid instead of choosing a random legal value.
        5_000.0 - (bid - target) * 200.0 - bid
      end
    rescue ArgumentError
      -100_000.0
    end

    def bot_contract_target(state, actor)
      player = player_key(state, actor)
      return BID_MINIMUM if player == nil

      hand = state[:hands].fetch(player, [])
      maximum = maximum_bid_for_hand(hand)
      estimate = bot_contract_estimate(state, actor)
      target = (estimate / BID_STEP).floor * BID_STEP
      target = [target, maximum].min
      target = [target, BID_MINIMUM].max

      # A player already on the barrel needs a contract of at least 120. Do
      # not waste a credible opportunity by deliberately stopping below it.
      barrel = state[:barrels].fetch(player, { active: false })
      if barrel[:active] && estimate >= BID_LIMIT_WITHOUT_MARRIAGE - 10
        target = [target, BID_LIMIT_WITHOUT_MARRIAGE].max
      end
      target
    end

    def bot_contract_estimate(state, actor)
      player = player_key(state, actor)
      return 0.0 if player == nil

      hand = state[:hands].fetch(player, [])
      card_points = hand.sum { |card| CARD_POINTS.fetch(card_rank(card)) }
      aces = hand.count { |card| card_rank(card) == "A" }
      protected_tens = SUITS.count do |suit|
        hand.include?("A#{suit}") && hand.include?("T#{suit}")
      end
      marriages = SUITS.select do |suit|
        hand.include?("K#{suit}") && hand.include?("Q#{suit}")
      end.map { |suit| MARRIAGE_POINTS.fetch(suit) }.sort.reverse
      access_factor = if aces >= 2
        0.75
      elsif aces == 1
        0.55
      elsif protected_tens > 0
        0.40
      else
        0.20
      end
      marriage_value = marriages.each_with_index.sum do |points, index|
        points * access_factor * (index == 0 ? 1.0 : 0.55)
      end
      expected_talon = state[:phase] == :bidding ? 10.0 : 0.0
      distribution = SUITS.sum do |suit|
        count = hand.count { |card| card_suit(card) == suit }
        count <= 1 ? 2.0 : 0.0
      end

      38.0 + card_points * 0.45 + aces * 11.0 + protected_tens * 6.0 +
        marriage_value + expected_talon + distribution
    end

    def bot_pass_card_score(state, actor, raw_card)
      card = raw_card.to_s
      hand = hand_for(state, actor)
      return -100_000.0 if !hand.include?(card)

      suit = card_suit(card)
      rank = card_rank(card)
      suit_count = hand.count { |candidate| card_suit(candidate) == suit }
      marriage = hand.include?("K#{suit}") && hand.include?("Q#{suit}")
      score = 300.0
      score -= CARD_POINTS.fetch(rank) * 18.0
      score -= RANKS.index(rank).to_i * 12.0
      score += 100.0 if suit_count == 1
      score += 35.0 if suit_count == 2
      score -= 2_000.0 if marriage && ["K", "Q"].include?(rank)
      score -= 500.0 if rank == "A"
      score -= 260.0 if rank == "T"
      score
    end

    def bot_surrender_score(state, actor)
      estimate = bot_contract_estimate(state, actor)
      deficit = state[:contract].to_f - estimate
      uses = state[:surrender_uses].fetch(player_key(state, actor), 0).to_i
      third_surrender_cost = uses >= 2 ? BARREL_DISTANCE : 0
      return -50_000.0 if deficit < 25.0
      return -50_000.0 if third_surrender_cost > 0 && deficit < 70.0

      50_000.0 + deficit * 100.0 - third_surrender_cost * 100.0
    end

    def bot_play_score(replay, actor, action)
      state = replay.state
      player = player_key(state, actor)
      mode, card = parse_play(action["card"])
      return -100_000.0 if player == nil || !hand_for(state, player).include?(card)

      rank = card_rank(card)
      card_points = CARD_POINTS.fetch(rank)
      strength = RANKS.index(rank).to_i
      card_cost = card_points * 18.0 + strength * 14.0
      new_trump = mode == "marriage" ? card_suit(card) : state[:trump]
      trick = state[:current_trick].to_a
      candidate_trick = trick + [{ player: player, card: card }]
      wins_now = same_user?(trick_winner(candidate_trick, new_trump), player)
      last_seat = candidate_trick.length == state[:players].length
      trick_points = candidate_trick.sum { |play| CARD_POINTS.fetch(card_rank(play[:card])) }
      taker = state[:taker]
      taker_need = [state[:contract].to_i - state[:round_points].fetch(taker, 0).to_i, 0].max
      own_need = same_user?(player, taker) ? taker_need : 0
      score = 0.0

      if mode != "marriage" && ["K", "Q"].include?(rank) &&
          hand_for(state, player).include?("K#{card_suit(card)}") &&
          hand_for(state, player).include?("Q#{card_suit(card)}")
        # Keep an undeclared marriage intact whenever another legal card is
        # available. This is especially important on the first trick, when a
        # marriage cannot yet be announced.
        score -= 8_000.0
      end

      if mode == "marriage"
        bonus = MARRIAGE_POINTS.fetch(card_suit(card))
        # Declaring now both secures the bonus and creates trump. It must
        # decisively beat the ordinary-play alternative for the same card.
        score += 20_000.0 + bonus * 100.0
        own_need = [own_need - bonus, 0].max
      end

      if trick.empty?
        higher = bot_higher_unseen_count(replay, player, card)
        if higher == 0
          score += 2_000.0 + card_points * 30.0
          score += [own_need, card_points + 12].min * 20.0 if same_user?(player, taker)
        else
          score -= card_cost
        end
        # Avoid leading an exposed ten while its ace is still outside the
        # bot's hand; an ace or a promoted ten remains a natural cashing lead.
        if rank == "T" && !hand_for(state, player).include?("A#{card_suit(card)}") && higher > 0
          score -= 700.0
        end
        return score
      end

      if last_seat
        if wins_now
          previous_winner = trick_winner(trick, state[:trump])
          score += 3_000.0 + trick_points * 45.0 - card_cost
          score += 2_000.0 if !same_user?(player, taker) && same_user?(previous_winner, taker)
          score += [own_need, trick_points].min * 35.0 if same_user?(player, taker)
        else
          winner = trick_winner(candidate_trick, new_trump)
          score -= card_cost
          score -= card_points * 45.0 if same_user?(winner, taker) && !same_user?(player, taker)
        end
        return score
      end

      if wins_now
        threats = bot_higher_unseen_count(replay, player, card)
        # A side-suit card may additionally be ruffed by a later player. This
        # is uncertainty, not knowledge of either opponent's hand.
        threats += 1 if new_trump != nil && card_suit(card) != new_trump
        probability = 1.0 / (threats + 1.0)
        score += probability * (2_000.0 + trick_points * 35.0)
        score -= (1.0 - probability) * card_cost
        score += probability * [own_need, trick_points].min * 25.0 if same_user?(player, taker)
      else
        current_winner = trick_winner(candidate_trick, new_trump)
        score -= card_cost
        score -= card_points * 25.0 if same_user?(current_winner, taker) && !same_user?(player, taker)
      end
      score
    rescue ArgumentError, KeyError
      -100_000.0
    end

    def bot_public_played_cards(replay)
      events = replay.accepted_events.to_a
      deal = events.rindex { |event| event["action"].to_s == "deal" }
      events = events[(deal + 1)..] if deal != nil
      events.filter_map do |event|
        next if event["action"].to_s != "play"

        _mode, card = parse_play(event["value"])
        card
      rescue ArgumentError
        nil
      end
    end

    def bot_higher_unseen_count(replay, actor, card)
      state = replay.state
      known = hand_for(state, actor).to_a + bot_public_played_cards(replay)
      rank = RANKS.index(card_rank(card)).to_i
      deck.count do |candidate|
        !known.include?(candidate) && card_suit(candidate) == card_suit(card) &&
          RANKS.index(card_rank(candidate)).to_i > rank
      end
    end

    def legal_cards(state, actor)
      hand = hand_for(state, actor)
      return hand.dup if state[:current_trick].empty?

      led = card_suit(state[:current_trick].first[:card])
      following = hand.select { |card| card_suit(card) == led }
      return following if !following.empty?

      if state[:trump] != nil
        trumps = hand.select { |card| card_suit(card) == state[:trump] }
        return trumps if !trumps.empty?
      end
      hand.dup
    end

    def marriage_available?(state, actor, card)
      return false if state[:phase] != :playing || !same_user?(state[:current_player], actor)
      return false if !state[:current_trick].empty? || state[:trick_number].to_i == 0
      return false if !["K", "Q"].include?(card_rank(card))

      suit = card_suit(card)
      hand = hand_for(state, actor)
      hand.include?("K#{suit}") && hand.include?("Q#{suit}")
    end

    def maximum_bid_for_hand(hand)
      marriage_points = SUITS.sum do |suit|
        hand.include?("K#{suit}") && hand.include?("Q#{suit}") ? MARRIAGE_POINTS.fetch(suit) : 0
      end
      [BID_LIMIT_WITHOUT_MARRIAGE + marriage_points, BID_MAXIMUM].min
    end

    def trick_winner(trick, trump)
      led = card_suit(trick.first[:card])
      trick.max_by do |play|
        suit = card_suit(play[:card])
        suit_value = if trump != nil && suit == trump
          2
        elsif suit == led
          1
        else
          0
        end
        [suit_value, RANKS.index(card_rank(play[:card])).to_i]
      end[:player]
    end

    def surface_card(state, viewer, card)
      if state[:phase] == :bidding && same_user?(state[:current_player], viewer)
        choices = legal_bid_values(state, viewer).map do |value|
          GameSurfaces::CardChoice.new(
            id: "bid:#{value}",
            label: value.to_s == "pass" ? _("Pass") : value.to_s,
            value: value
          )
        end
        return GameSurfaces::Card.new(
          id: card,
          label: card_label(card),
          value: card,
          choices: choices,
          choice_header: _("Choose your bid")
        )
      end
      if state[:phase] == :playing
        normal = GameSurfaces::CardChoice.new(
          id: "normal",
          label: _("Play without declaring a marriage"),
          value: "normal|#{card}"
        )
        if marriage_available?(state, viewer, card)
          marriage = GameSurfaces::CardChoice.new(
            id: "marriage",
            label: _("Declare the marriage"),
            value: "marriage|#{card}"
          )
          return GameSurfaces::Card.new(
            id: card,
            label: card_label(card),
            value: card,
            choices: [normal, marriage],
            shift_choice: "marriage"
          )
        end
        return GameSurfaces::Card.new(
          id: card,
          label: card_label(card),
          value: "normal|#{card}",
          shift_choice: "marriage"
        )
      end
      GameSurfaces::Card.new(
        id: card, label: card_label(card), value: card, shift_choice: "marriage"
      )
    end

    def hand_header(state, viewer)
      passing_prompt(state, viewer) || _("Your hand")
    end

    def passed_card_text(taker, target, card, viewer)
      if same_user?(taker, viewer)
        return _("You gave %{card} to %{player}.") % {
          card: card_label(card),
          player: participant_name(target)
        }
      end
      if same_user?(target, viewer)
        return _("%{player} gave you %{card}.") % {
          player: participant_name(taker),
          card: card_label(card)
        }
      end

      _("%{taker} gave a card to %{player}.") % {
        taker: participant_name(taker),
        player: participant_name(target)
      }
    end

    def passing_prompt(state, viewer)
      if state[:phase] == :discarding && same_user?(state[:taker], viewer)
        return _("Choose a card to set aside. Remaining: %{count}.") % { count: talon_size(state) - state[:pass_index] }
      end
      return nil if state[:phase] != :passing || !same_user?(state[:taker], viewer)

      target = pass_recipients(state)[state[:pass_index].to_i]
      return nil if target == nil

      _("Choose a card to give to %{player}.") % { player: participant_name(target) }
    end

    def two_players?(state)
      state[:options]["variant"] == "two_players"
    end

    def talon_size(state)
      two_players?(state) ? state[:options]["talon_size"].to_i : 3
    end

    def surrender_command(state, viewer)
      return nil if !surrender_available?(state, viewer)
      GameSurfaces::CommandPanelSpec.new(
        commands: [
          GameSurfaces::Command.new(
            id: "surrender",
            label: _("Surrender the deal"),
            enabled: true,
            payload: {}
          )
        ]
      )
    end

    def bid_choice_data(state, viewer, final:)
      values = final ? legal_contract_values(state, viewer) : legal_bid_values(state, viewer)
      choices = values.map do |value|
        ShortcutChoice.new(
          value: value,
          label: value.to_s == "pass" ? _("Pass") : value.to_s
        )
      end
      {
        kind: :choice,
        label: final ? _("set the final contract") : _("make a bid"),
        prompt: final ? _("Choose the contract value") : _("Choose your bid"),
        action_kind: "command",
        action_name: final ? "contract" : "bid",
        value_key: "bid",
        choices: choices
      }
    end

    def hand_text(state, viewer)
      hand = hand_for(state, viewer).sort_by { |card| card_sort_key(card) }
      return _("Your hand is empty.") if hand.empty?
      _("Your hand: %{cards}.") % { cards: hand.map { |card| card_label(card) }.join(", ") }
    end

    def table_cards_text(state)
      return _("No cards have been played in this trick.") if state[:current_trick].empty?
      state[:current_trick].map do |play|
        _("%{player}: %{card}") % {
          player: participant_name(play[:player]),
          card: card_label(play[:card])
        }
      end.join("; ")
    end

    def scores_text(state, sorted: false)
      players = sorted ? score_announcement_order(state[:players], state[:scores]) : state[:players]
      _("Scores: %{scores}.") % {
        scores: players.map do |player|
          text = _("%{player}: %{score}") % {
            player: participant_name(player),
            score: state[:scores][player]
          }
          text += _(", on the barrel") if state[:barrels][player][:active]
          text
        end.join("; ")
      }
    end

    def statistics_text(state)
      _("Statistics: %{statistics}.") % {
        statistics: state[:players].map do |player|
          barrel = state[:barrels][player]
          suffix = barrel[:active] ? _(", on the barrel, %{deals} deals left") % { deals: barrel[:deals_left] } : ""
          _("%{player}: zeros %{zeros}/3, surrenders %{surrenders}/3%{barrel}") % {
            player: participant_name(player),
            zeros: state[:zero_rounds][player],
            surrenders: state[:surrender_uses][player],
            barrel: suffix
          }
        end.join("; ")
      }
    end

    def bids_text(state)
      return _("The auction has not started.") if state[:round].to_i == 0
      entries = state[:players].map do |player|
        value = state[:bids][player]
        value = _("not bid yet") if value == nil
        value = _("passed") if value.to_s == "pass"
        _("%{player}: %{bid}") % { player: participant_name(player), bid: value }
      end
      result = _("Auction: %{bids}.") % { bids: entries.join("; ") }
      if state[:contract] != nil
        result += " " + _("Current contract: %{contract}, bidder: %{player}.") % {
          contract: state[:contract],
          player: participant_name(state[:taker] || state[:current_bidder])
        }
      end
      result
    end

    def hand_for(state, actor)
      player = player_key(state, actor)
      player == nil ? [] : state[:hands].fetch(player, [])
    end

    def player_key(state, actor)
      state[:players].find { |player| same_user?(player, actor) }
    end

    def deck
      SUITS.product(RANKS).map { |suit, rank| "#{rank}#{suit}" }
    end

    def shuffled_deck(seed)
      deck.sort_by { |card| Digest::SHA256.hexdigest("#{seed}\0#{card}") }
    end

    def parse_deal(value)
      fields = value.to_s.split("|", -1)
      raise ArgumentError, "invalid deal" if fields.length != 3
      round = Integer(fields[0], 10)
      dealer = Integer(fields[1], 10)
      seed = fields[2].to_s.downcase
      raise ArgumentError, "invalid deal seed" if seed !~ /\A[0-9a-f]{32}\z/
      [round, dealer, seed]
    end

    def random_seed(source)
      source.roll(count: 16, sides: 256).values.map do |value|
        (value.to_i - 1).to_s(16).rjust(2, "0")
      end.join
    end

    def parse_play(value)
      mode, card = value.to_s.split("|", 2)
      raise ArgumentError, "invalid play" if card == nil || !deck.include?(card)
      [mode, card]
    end

    def card_rank(card)
      card.to_s[0]
    end

    def card_suit(card)
      card.to_s[1]
    end

    def card_label(card)
      _("%{rank} of %{suit}") % {
        rank: RANK_NAMES.fetch(card_rank(card), card_rank(card)),
        suit: SUIT_NAMES.fetch(card_suit(card), card_suit(card))
      }
    end

    def card_sort_key(card)
      playroom_hand_sort_key(card)
    end

    def round_nearest_five(value)
      (value.to_f / 5.0).round * 5
    end

    def round_up_five(value)
      (value.to_f / 5.0).ceil * 5
    end

    def score_change_text(player, delta)
      name = participant_name(player)
      if delta.to_i > 0
        _("%{player} gained %{points} points.") % { player: name, points: delta.to_i }
      elsif delta.to_i < 0
        _("%{player} lost %{points} points.") % { player: name, points: -delta.to_i }
      else
        _("%{player} gained no points.") % { player: name }
      end
    end

    def round_score_text(player, collected, delta)
      values = {
        player: participant_name(player),
        collected: collected.to_i,
        points: delta.to_i.abs
      }
      if delta.to_i < 0
        _("%{player}, collected %{collected}, lost %{points}.") % values
      else
        _("%{player}, collected %{collected}, awarded %{points}.") % values
      end
    end

    def cycle_notice(player, occurrence, kind)
      ordinal = [[occurrence.to_i, 1].max, 3].min
      if kind.to_sym == :surrender
        return _("%{player}: first surrender.") % { player: participant_name(player) } if ordinal == 1
        return _("%{player}: second surrender.") % { player: participant_name(player) } if ordinal == 2

        _("%{player}: third surrender.") % { player: participant_name(player) }
      else
        return _("%{player}: first zero.") % { player: participant_name(player) } if ordinal == 1
        return _("%{player}: second zero.") % { player: participant_name(player) } if ordinal == 2

        _("%{player}: third zero.") % { player: participant_name(player) }
      end
    end
  end
end
