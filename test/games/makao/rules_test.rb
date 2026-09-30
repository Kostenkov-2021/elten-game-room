require_relative '../../support/new_games_fixture'

players = %w[Alice Bob Carol]
repository = NewGames116Repository.new(players)

makao = GameRoomGames::Makao.new
assert(makao.supports_bots?, "Makao has no bot")
assert(makao.default_options["profile"] == "simple" && !makao.default_options["jokers"], "Makao does not default to the simple profile")
assert(makao.default_options["bot_delay"] == 1, "Makao does not default to a one-second bot delay")
assert(makao.options_error(makao.default_options.merge("bot_delay" => 0)) == nil, "Makao rejected disabled intentional delay")
assert(makao.options_error(makao.default_options.merge("bot_delay" => 6)) != nil, "Makao accepted a bot delay above five seconds")
makao_definitions = makao.option_definitions.to_h { |definition| [definition.key, definition] }
assert(!makao.option_visible?(makao_definitions["jokers"], makao.default_options),
  "Makao shows custom rule switches for a ready-made profile")
assert(makao.option_visible?(makao_definitions["jokers"], makao.default_options.merge("profile" => "custom")),
  "Makao hides custom rule switches for the custom profile")
assert(!makao.option_visible?(makao_definitions["hand_size"], makao.default_options.merge("profile" => "joker")),
  "Makao shows the fixed hand size in the joker profile")
joker_options = makao.normalize_options("profile" => "joker")
assert(joker_options["jokers"] && joker_options["hand_size"] == 5, "The agreed joker profile is incomplete")
universal_joker_choices = makao.send(:card_choices_for,
  makao.send(:initial_state, players, joker_options), "X0")
assert(universal_joker_choices.length == 52 && universal_joker_choices.include?("2C") &&
  universal_joker_choices.include?("QD") && universal_joker_choices.include?("AS"),
  "Makao joker cannot represent every ordinary card")
makao_session = { "options" => JSON.generate(joker_options) }
makao_events = []
makao_replay = makao.replay(makao_session, makao_events, repository)
assert(makao.bot_move_delay(makao_replay, "Alice") == 1, "Makao ignored the configured bot delay")
makao_replay = append_action(makao, makao_session, repository, makao_events, makao_replay, "Alice",
  makao.automatic_action(makao_replay, "Alice"), context_for)
assert(makao_replay.state[:hands].values.all? { |hand| hand.length == 5 }, "Makao did not deal five cards")
makao_counts = makao.custom_game_shortcuts(makao_replay, "Alice").find do |shortcut|
  shortcut.key == "e" && shortcut.kind == :announcement && shortcut.modifiers.to_a.empty?
end
assert(makao_counts && makao_counts.message == "Alice, 5. Bob, 5. Carol, 5.",
  "Makao E does not read concise card counts")
paced_makao = makao.replay(
  { "options" => JSON.generate(joker_options.merge("bot_delay" => 5)) },
  [],
  repository
)
assert(makao.bot_move_delay(paced_makao, "Alice") == 5, "Makao did not apply a five-second bot delay")
makao_actor = makao_replay.current_player
makao_move = makao.legal_actions(makao_replay, makao_actor).find { |action| action["action"] == "play" } ||
  makao.legal_actions(makao_replay, makao_actor).find { |action| action["action"] == "draw" }
makao_replay = append_action(makao, makao_session, repository, makao_events, makao_replay, makao_actor, makao_move)
assert(makao_replay.accepted_events.length == 2, "Makao rejected its first legal action")

skip_state = makao.send(:initial_state, players, makao.normalize_options("profile" => "joker"))
skip_state.update(phase: :playing, current_player: "Alice", hands: {
  "Alice" => %w[4C 4D 9S], "Bob" => %w[5D 6D], "Carol" => %w[7H 8H]
}, discard: ["5C"], declared_suit: "C")
skip_history = []
fours = { "id" => 1, "actor" => "Alice", "action" => "play", "value" => "4C,4D|" }
assert(makao.send(:apply_play, skip_state, fours, "Alice", repository, skip_history), "Makao did not accept a packet of fours")
assert(skip_state[:skip_penalty] == 2 && skip_state[:current_player] == "Bob", "Makao did not offer the accumulated fours to the next player")
accept_skip = { "id" => 2, "actor" => "Bob", "action" => "accept_skip", "value" => "" }
assert(makao.send(:apply_accept_skip, skip_state, accept_skip, "Bob", repository, skip_history), "Makao did not accept the waiting penalty")
assert(skip_state[:current_player] == "Carol" && skip_state[:skip_turns]["Bob"] == 1, "Makao did not preserve the remaining waiting turn")
assert(makao.send(:advance_player, skip_state, "Carol", 1) == "Alice", "Makao did not skip the penalized player on the next circuit")

forced_draw_state = makao.send(:initial_state, players, joker_options)
forced_draw_state.update(phase: :playing, current_player: "Bob", declared_suit: "C", discard: ["2C"],
  draw_penalty: 2, penalty_kind: "draw",
  hands: { "Alice" => ["9S"], "Bob" => %w[5D 6D], "Carol" => ["7H"] })
forced_draw_replay = GameRoomGames::Replay.new(players: players, current_player: "Bob", state: forced_draw_state)
assert(makao.automatic_action(forced_draw_replay, "Bob") == { "kind" => "command", "action" => "draw" },
  "Makao did not automatically accept an unavoidable draw penalty")
assert(makao.automatic_action_allowed?(forced_draw_replay, "Bob", table_owner: "Alice"),
  "Makao did not allow a non-owner to submit their own unavoidable penalty")
assert(!makao.automatic_action_allowed?(forced_draw_replay, "Carol", table_owner: "Alice"),
  "Makao allowed another non-owner to submit somebody else's penalty")
assert(!makao.automatic_action_allowed?(forced_draw_replay, "Host", table_owner: "Host"),
  "Makao allowed an observing table owner to duplicate a human player's automatic penalty")
forced_draw_state[:hands]["Bob"] << "3D"
assert(makao.automatic_action(forced_draw_replay, "Bob") == nil,
  "Makao automatically drew a penalty although the player could defend")

forced_skip_state = makao.send(:initial_state, players, joker_options)
forced_skip_state.update(phase: :playing, current_player: "Bob", declared_suit: "C", discard: ["4C"],
  skip_penalty: 2,
  hands: { "Alice" => ["9S"], "Bob" => %w[5D 6D], "Carol" => ["7H"] })
forced_skip_replay = GameRoomGames::Replay.new(players: players, current_player: "Bob", state: forced_skip_state)
assert(makao.automatic_action(forced_skip_replay, "Bob") == { "kind" => "command", "action" => "accept_skip" },
  "Makao did not automatically accept an unavoidable waiting penalty")
forced_skip_state[:hands]["Bob"] << "4D"
assert(makao.automatic_action(forced_skip_replay, "Bob") == nil,
  "Makao automatically accepted a waiting penalty although the player could defend")

joker_packet_state = makao.send(:initial_state, players, joker_options)
joker_packet_state.update(phase: :playing, current_player: "Alice", declared_suit: "C", discard: ["7C"],
  hands: { "Alice" => %w[X0 7D 9S], "Bob" => %w[5D 6D], "Carol" => %w[7H 8H] })
joker_packet_history = []
assert(makao.send(:apply_play, joker_packet_state,
  { "id" => 27, "actor" => "Alice", "action" => "play", "value" => "X0,7D|" },
  "Alice", repository, joker_packet_history), "Makao rejected a joker inferred as the packet's ordinary rank")
assert(joker_packet_state[:declared_suit] == "D",
  "Makao did not preserve the effective suit of a packet containing a joker")

king_state = makao.send(:initial_state, players, joker_options)
king_state.update(phase: :playing, current_player: "Bob", declared_suit: "S", discard: ["KS"],
  draw_penalty: 5, penalty_kind: "K",
  hands: { "Alice" => ["9S"], "Bob" => %w[KH 8D], "Carol" => ["7H"] })
king_history = []
assert(makao.send(:apply_play, king_state,
  { "id" => 28, "actor" => "Bob", "action" => "play", "value" => "KH|" },
  "Bob", repository, king_history), "Makao rejected the defensive king of hearts")
assert(king_state[:draw_penalty] == 10 && king_state[:current_player] == "Carol",
  "Makao defensive king did not pass an accumulated ten-card penalty")

packet_order_state = makao.send(:initial_state, players, makao.normalize_options("profile" => "simple"))
packet_order_state.update(phase: :playing, current_player: "Alice", declared_suit: "C", discard: ["5C"],
  hands: { "Alice" => %w[7D 7C 9S], "Bob" => ["5D"], "Carol" => ["6H"] })
assert(makao.send(:validate_packet, packet_order_state, "Alice", %w[7D 7C], "") == :illegal_card,
  "Makao accepted a packet whose first card did not match the table")
assert(makao.send(:validate_packet, packet_order_state, "Alice", %w[7C 7D], "") == :ok,
  "Makao rejected a packet whose first card matched the table")

puts 'PASS makao: rules, legal actions and options'
