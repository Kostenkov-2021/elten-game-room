require_relative "../support/translation_reference"
require_relative "../support/ui"
require_relative "../../lib/game_surfaces"
require_relative "../../lib/game_screen"
require_relative "../../games/uno"
require_relative "../../games/makao"
require_relative "../../games/ninety_nine"
require_relative "../../games/spades"
require_relative "../../games/tysiac"

def assert(condition, message)
  raise message unless condition
end

def replay_for(state)
  GameRoomGames::Replay.new(
    players: state[:players], current_player: state[:current_player],
    winner: state[:winner], draw: false, accepted_events: [], history: [], state: state
  )
end

def navigation_shortcuts(game, state, viewer = "Alice")
  game.send(:playable_card_shortcuts, replay_for(state), viewer)
end

def shortcut(shortcuts, direction)
  modifiers = direction < 0 ? [:shift] : []
  shortcuts.find { |item| item.key == "z" && item.modifiers == modifiers }
end

def hand_spec(ids, choices: {})
  cards = ids.map do |id|
    variants = choices.fetch(id, []).map do |choice|
      GameSurfaces::CardChoice.new(id: choice, label: choice, value: "#{id}|#{choice}")
    end
    GameSurfaces::Card.new(id: id, label: "card #{id}", value: id, choices: variants)
  end
  GameSurfaces::CardTableSpec.new(zones: [
    GameSurfaces::CardZoneSpec.new(
      id: "hand", header: "Hand", cards: cards, empty_label: "Empty",
      hand_order: ids.dup, hand_epoch: "Alice:1"
    )
  ])
end

payload = {
  "hand_id" => "hand", "card_ids" => %w[A C], "direction" => 1,
  "auto_card_id" => nil, "auto_action" => nil,
  "empty_message" => "No playable card", "shortcut" => "z"
}
surface = GameSurfaces.build(hand_spec(%w[A B C D]))
surface.fields.first.index = 1
assert(surface.handle_command("navigate_playable_card", payload), "Z was not handled by the shared hand")
assert(surface.fields.first.index == 2, "Z did not choose the next playable physical card")
assert(surface.fields.first.last_focus_spoken, "Z did not speak the newly focused card")
assert(surface.fields.first.last_focus_header == "", "Z repeated the hand caption instead of just the card")
assert(surface.fields.first.header == "Hand", "Z changed the hand's persistent caption")
surface.handle_command("navigate_playable_card", payload)
assert(surface.fields.first.index == 0, "Z did not wrap to the first playable card")
surface.handle_command("navigate_playable_card", payload.merge("direction" => -1, "shortcut" => "shift+z"))
assert(surface.fields.first.index == 2, "Shift+Z did not wrap to the previous playable card")
assert(surface.fields.first.last_focus_header == "", "Shift+Z repeated the hand caption")

$spoken_messages.clear
surface.handle_command("navigate_playable_card", payload.merge("card_ids" => []))
assert($spoken_messages.last == "No playable card", "an empty playable set did not give the short message")

automatic = {
  "kind" => "card", "action" => "select", "zone" => "hand",
  "card" => "C", "card_id" => "C"
}
result = surface.handle_command("navigate_playable_card", payload.merge(
  "card_ids" => ["C"], "auto_card_id" => "C", "auto_action" => automatic
))
assert(result.is_a?(GameSurfaces::Action), "one unambiguous physical card was not returned as an action")
assert(result.to_h.reject { |key, _value| key == "source" } == automatic,
  "automatic navigation changed the game's legal action")
assert(result.source == "shortcut:z", "automatic navigation lost its shortcut source")
screen_result = GameScreen.allocate.send(
  :activate_game_shortcut,
  GameRoomGames::GameShortcut.new(
    key: "z", label: "next", kind: :surface, action_kind: "surface",
    action_name: "navigate_playable_card", payload: payload.merge(
      "card_ids" => ["C"], "auto_card_id" => "C", "auto_action" => automatic
    )
  ),
  surface
)
assert(screen_result.is_a?(GameSurfaces::Action), "GameScreen swallowed the automatic card action")

$spoken_messages.clear
choosing = GameSurfaces.build(hand_spec(%w[A B], choices: { "A" => ["mode"] }))
choosing.fields.first.trigger(:select, [0])
choosing.handle_command("navigate_playable_card", payload.merge("card_ids" => ["A"]))
assert($spoken_messages.last == "Finish or cancel the current card choice first.",
  "Z replaced an unfinished card choice")

packet_cards = %w[A B C].map do |id|
  GameSurfaces::Card.new(id: id, label: "card #{id}", value: id, choices: [])
end
packet_spec = GameSurfaces::PacketCardSpec.new(
  id: "packet_hand", header: "Hand", cards: packet_cards, action_name: "play",
  allow_packet: true, empty_label: "Empty", hand_order: %w[A B C], hand_epoch: "Alice:1"
)
packet = GameSurfaces.build(packet_spec)
packet.fields.first.index = 0
packet.handle_command("navigate_playable_card", payload.merge(
  "hand_id" => "packet_hand", "card_ids" => ["C"]
))
assert(packet.fields.first.index == 2, "packet-card navigation did not use the shared rule")
assert(packet.fields.first.last_focus_header == "", "packet-card Z repeated the hand caption")
prepared_state = packet.state
prepared_state["selected_ids"] = ["A"]
packet = GameSurfaces.build(packet_spec, state: prepared_state)
$spoken_messages.clear
packet.handle_command("navigate_playable_card", payload.merge(
  "hand_id" => "packet_hand", "card_ids" => ["C"]
))
assert($spoken_messages.last == "Finish or clear the prepared packet first.",
  "Z discarded or ignored a prepared packet")

command = GameSurfaces::CommandPanelSpec.new(commands: [
  GameSurfaces::Command.new(id: "wait", label: "Wait", enabled: true, payload: {})
])
composite = GameSurfaces.build(GameSurfaces::CompositeSpec.new(parts: [
  GameSurfaces::SurfacePart.new(id: "command", surface: command),
  GameSurfaces::SurfacePart.new(id: "hand", surface: packet_spec)
]))
assert(composite.handle_command("navigate_playable_card", payload.merge(
  "hand_id" => "packet_hand", "card_ids" => ["C"]
)), "a composite surface did not delegate Z to its hand")
assert(composite.command_field_index == 1, "a composite surface reported the wrong hand field")
assert(composite.fields[1].last_focus_header == "", "composite Z repeated the hand caption")
ordinary_list = GameSurfaces::RefreshAwareListBox.new(["option"], header: "Other list")
ordinary_list.focus
assert(ordinary_list.last_focus_header == "Other list", "card navigation suppressed an unrelated list's caption")
packet.fields.first.focus
assert(packet.fields.first.last_focus_header == "Hand", "ordinary entry to a hand lost its caption")

players = %w[Alice Bob Carol]

uno = GameRoomGames::Uno.new
uno_state = uno.send(:initial_state, players, uno.default_options)
uno_state.update(
  phase: :playing, current_player: "Alice", discard: ["R9a"], colour: "R",
  hands: { "Alice" => %w[R5a G2a], "Bob" => ["B1a"], "Carol" => ["Y1a"] }
)
uno_shortcuts = navigation_shortcuts(uno, uno_state)
assert(uno_shortcuts.length == 2, "ordinary UNO did not expose Z and Shift+Z")
assert(shortcut(uno_shortcuts, 1).payload["auto_card_id"] == "R5a",
  "ordinary UNO did not recognize its single unambiguous card")
uno_state[:hands]["Alice"] = %w[NW0 G2a]
wild = shortcut(navigation_shortcuts(uno, uno_state), 1)
assert(wild.payload["card_ids"] == ["NW0"] && wild.payload["auto_action"] == nil,
  "a Wild card was allowed to skip its required colour decision")
%w[straights interceptions super_interceptions buzzers].each do |option|
  blocked = Marshal.load(Marshal.dump(uno_state))
  blocked[:options][option] = true
  assert(navigation_shortcuts(uno, blocked).empty?, "UNO navigation remained active with #{option}")
end
uno_state[:current_player] = "Bob"
assert(navigation_shortcuts(uno, uno_state).empty?, "UNO navigation leaked outside the viewer's turn")

ninety_nine = GameRoomGames::NinetyNine.new
ninety_state = ninety_nine.send(:initial_state, players, ninety_nine.default_options)
ninety_state.update(phase: :playing, current_player: "Alice", total: 20)
ninety_state[:hands]["Alice"] = ["03C"]
ordinary_99 = shortcut(navigation_shortcuts(ninety_nine, ninety_state), 1)
assert(ordinary_99.payload["auto_card_id"] == "03C" && ordinary_99.payload["auto_action"] != nil,
  "99 did not automate one card with one mode")
ninety_state[:hands]["Alice"] = ["0AC"]
ace_99 = shortcut(navigation_shortcuts(ninety_nine, ninety_state), 1)
assert(ace_99.payload["card_ids"] == ["0AC"] && ace_99.payload["auto_action"] == nil,
  "99 automated an ace although it has two values")

spades = GameRoomGames::Spades.new
spades_state = {
  players: players, phase: :playing, current_player: "Alice", winner: nil,
  hands: { "Alice" => %w[2C AS], "Bob" => [], "Carol" => [] },
  current_trick: [{ player: "Bob", card: "KC" }], spades_broken: true
}
spades_z = shortcut(navigation_shortcuts(spades, spades_state), 1)
assert(spades_z.payload["auto_card_id"] == "2C" && spades_z.payload["auto_action"] != nil,
  "Spades did not automate its only legal card")

tysiac = GameRoomGames::Tysiac.new
tysiac_state = tysiac.send(:initial_state, players, tysiac.default_options)
tysiac_state.update(
  phase: :playing, current_player: "Alice", current_trick: [{ player: "Bob", card: "KC" }],
  hands: { "Alice" => %w[9C AS], "Bob" => [], "Carol" => [] }
)
tysiac_z = shortcut(navigation_shortcuts(tysiac, tysiac_state), 1)
assert(tysiac_z.payload["auto_card_id"] == "9C" && tysiac_z.payload["auto_action"] != nil,
  "Tysiac did not automate one ordinary legal play")
tysiac_state.update(current_trick: [], trick_number: 1)
tysiac_state[:hands]["Alice"] = %w[QH KH]
marriage_z = shortcut(navigation_shortcuts(tysiac, tysiac_state), 1)
assert(marriage_z.payload["auto_action"] == nil,
  "Tysiac automated a hand containing an optional marriage")

makao = GameRoomGames::Makao.new
makao_state = makao.send(:initial_state, players, makao.default_options)
makao_state.update(
  phase: :playing, current_player: "Alice", discard: ["9H"], declared_suit: "H",
  hands: { "Alice" => %w[9S 5D], "Bob" => ["6C"], "Carol" => ["7D"] }
)
makao_z = shortcut(navigation_shortcuts(makao, makao_state), 1)
assert(makao_z.payload["card_ids"] == ["9S"] && makao_z.payload["auto_card_id"] == "9S" && makao_z.payload["auto_action"] != nil,
  "Makao did not automate its only ordinary playable card without a packet alternative")
makao_surface = GameSurfaces.build(makao.surface_spec(replay_for(makao_state), "Alice"))
makao_action = GameScreen.allocate.send(:activate_game_shortcut, makao_z, makao_surface)
assert(makao_action.is_a?(GameSurfaces::Action), "Makao Z did not return a game action")
status, plan = makao.action_for(makao_action, replay_for(makao_state), "Alice")
assert(status == :ok && plan.events.first.action == "play" && plan.events.first.value == "9S|",
  "Makao rejected or changed the automatic single-card play")

# Ordinary Enter uses the same one-card wire representation, not a request to
# prepare a multi-card packet. Both paths must be accepted by action_for.
entered = []
makao_surface.on_action { |action| entered << action }
makao_surface.fields.first.index = makao_surface.state["hand_cursor"]["ids"].index("9S")
makao_surface.fields.first.trigger(:select, [makao_surface.fields.first.index])
status, plan = makao.action_for(entered.last, replay_for(makao_state), "Alice")
assert(status == :ok && plan.events.first.value == "9S|", "Enter did not play one ordinary Makao card")
makao_state[:hands]["Alice"] = ["9S"]
assert(shortcut(navigation_shortcuts(makao, makao_state), -1).payload["auto_card_id"] == "9S",
  "Makao treated a one-card hand as a possible multi-card packet")
entered.clear
single_hand = GameSurfaces.build(makao.surface_spec(replay_for(makao_state), "Alice"))
single_hand.on_action { |action| entered << action }
single_hand.fields.first.trigger(:select, [0])
status, plan = makao.action_for(entered.last, replay_for(makao_state), "Alice")
assert(status == :ok && plan.events.first.value == "9S|", "Enter rejected a one-card Makao hand")
makao_state[:current_player] = "Bob"
assert(navigation_shortcuts(makao, makao_state).empty?, "Makao Z leaked outside the viewer's turn")
makao_state[:current_player] = "Alice"

# Only 5H can start the move, but it can be followed by 5D. Do not silently
# replace that genuine choice with a single-card play.
makao_state[:hands]["Alice"] = %w[5H 5D]
makao_z = shortcut(navigation_shortcuts(makao, makao_state), 1)
assert(makao_z.payload["card_ids"] == ["5H"] && makao_z.payload["auto_action"] == nil,
  "Makao automated a card which could start a legal multi-card packet")
%w[AH X0].each do |card|
  makao_state[:hands]["Alice"] = [card]
  makao_z = shortcut(navigation_shortcuts(makao, makao_state), 1)
  assert(makao_z.payload["card_ids"] == [card] && makao_z.payload["auto_action"] == nil,
    "Makao skipped the required declaration for #{card}")
end
makao_state[:options]["jack_requests_rank"] = true
makao_state[:hands]["Alice"] = ["JH"]
assert(shortcut(navigation_shortcuts(makao, makao_state), 1).payload["auto_action"] == nil,
  "Makao skipped the jack's rank request")
makao_state[:options]["ace_changes_suit"] = false
makao_state[:hands]["Alice"] = ["AH"]
assert(shortcut(navigation_shortcuts(makao, makao_state), 1).payload["auto_card_id"] == "AH",
  "a disabled ace rule still blocked an otherwise ordinary single-card play")

single = { "kind" => "card_packet", "action" => "play", "cards" => '["5D"]' }
multiple = single.merge("cards" => '["5D","5C"]')
assert(makao.move_error_for(:illegal_card, selection: single, replay: replay_for(makao_state)) == "This card cannot be played now.",
  "one-card rejection still refers to a packet")
makao_state[:draw_penalty] = 2
assert(makao.move_error_for(:illegal_card, selection: single, replay: replay_for(makao_state)) == "This card does not defend against the draw penalty.",
  "one-card defence rejection still refers to a packet")
assert(makao.move_error_for(:illegal_card, selection: multiple, replay: replay_for(makao_state)) == "The first card in the packet does not defend against the draw penalty.",
  "multi-card rejection lost the packet explanation")
assert(makao.move_error_for(:invalid_packet, selection: single) == "This card requires a valid declaration.",
  "a missing single-card declaration was described as an invalid packet")
assert(makao.move_error_for(:card_not_in_hand, selection: single) == "This card is not in your hand.",
  "a missing single card was described as multiple cards")

makao_state[:draw_penalty] = 0
makao_state[:skip_penalty] = 1
assert(makao.move_error_for(:illegal_card, selection: single, replay: replay_for(makao_state)) == "This card does not defend against the waiting penalty.",
  "one-card waiting defence still refers to a packet")
makao_state[:skip_penalty] = 0
makao_state[:requested_rank] = "7"
assert(makao.move_error_for(:illegal_card, selection: single, replay: replay_for(makao_state)) == "This card does not satisfy the requested rank.",
  "one-card requested-rank rejection still refers to a packet")
assert(makao.move_error_for(:not_your_turn, selection: { "kind" => "command", "action" => "draw" }) == makao.move_error(:not_your_turn),
  "singular errors changed the unrelated command rejection")

mo = File.binread(File.expand_path("../../locale/PL.mo", __dir__))
count, originals, translations = mo.byteslice(8, 12).unpack("V3")
catalog = count.times.to_h do |index|
  length, start = mo.byteslice(originals + index * 8, 8).unpack("V2")
  original = mo.byteslice(start, length).force_encoding("UTF-8")
  length, start = mo.byteslice(translations + index * 8, 8).unpack("V2")
  [original, mo.byteslice(start, length).force_encoding("UTF-8")]
end
GameRoomTest::TranslationReference.fetch("playable_cards").each do |original, translation|
  assert(catalog[original] == translation, "uncompiled Polish single-card error: #{original}")
end

puts "PASS playable-card navigation: directions, wrapping, focus, safe automation, choices and game policies"
