require_relative "../support/card_hand_cursor"

[false, true].each do |packet|
  [[3, %w[A B C], "C"], [1, %w[A C D], "A"], [0, %w[B C D], "B"]].each do |index, remaining, expected|
    surface = GameSurfaces.build(hand_spec(%w[A B C D], packet: packet))
    surface.fields.first.index = index
    field = surface.fields.first
    surface = GameSurfaces.reconcile(hand_spec(remaining, packet: packet), previous: surface)
    assert(surface.fields.first.equal?(field), "Rebuilt the card list")
    assert(selected(surface) == expected, "Wrong predecessor #{packet}: #{index}")
    assert(surface.take_cursor_announcement(0) == expected, "Missing cursor speech")
    assert(surface.take_cursor_announcement(0) == nil, "Repeated cursor speech")
    surface.update_spec(hand_spec(remaining, packet: packet))
    assert(surface.take_cursor_announcement(0) == nil, "Unchanged refresh spoke a card")
  end
  surface = GameSurfaces.build(hand_spec(%w[B D], packet: packet))
  surface.update_spec(hand_spec(%w[B D Z A], packet: packet))
  assert(surface.fields.first.options == %w[B D Z A], "New cards were not appended in draw order")
  assert(selected(surface) == "A", "Did not choose the LAST received card")
  assert(surface.take_cursor_announcement(0) == "A", "Wrong received card speech")
  surface.update_spec(hand_spec(%w[B Z A C], packet: packet))
  assert(selected(surface) == "C", "Play + draw did not prioritize the draw")
  surface.take_cursor_announcement(0)
  surface.update_spec(hand_spec([], packet: packet))
  assert(surface.fields.first.options.empty? && surface.take_cursor_announcement(0) == nil, "Empty hand spoke a card")
  surface.update_spec(hand_spec(%w[A C D], packet: packet, epoch: "2"))
  assert(selected(surface) == "A" && surface.take_cursor_announcement(0) == nil, "New deal treated as draw")

  duplicates = GameSurfaces.build(hand_spec(%w[A B C], packet: packet, duplicate_labels: true))
  duplicates.update_spec(hand_spec(%w[B C], packet: packet, duplicate_labels: true))
  assert(duplicates.take_cursor_announcement(0) == "same card", "Identical label hid a different card")

  # An unchanged hand does not move; receive no extra speech in a choice menu.
  choosing = GameSurfaces.build(hand_spec(%w[A B], packet: packet, choices: true))
  choosing.fields.first.trigger(:select, [0])
  choosing.update_spec(hand_spec(%w[A B], packet: packet, choices: true))
  assert(choosing.fields.first.options == ["Choice"], "Remote update closed the choice menu")
  assert(choosing.take_cursor_announcement(0) == nil, "Choice menu announced a hand card")
  emitted = []
  choosing.on_action { |action| emitted << action }
  choosing.fields.first.trigger(:select, [0])
  assert(emitted.length == 1, "Choice handler lost or duplicated")
  choosing.fields.first.trigger(:select, [0])
  restored_choice = GameSurfaces.build(hand_spec(%w[A B], packet: packet, choices: true, epoch: "2"), state: choosing.state)
  assert(restored_choice.fields.first.options == %w[A B], "New deal restored an old choice menu")
  choosing.update_spec(hand_spec(%w[A B], packet: packet, choices: true, epoch: "2"))
  assert(choosing.fields.first.options == %w[A B], "New deal kept an old choice menu in the reused hand")
end

prepared_state = GameSurfaces.build(hand_spec(%w[A B], packet: true)).state
prepared_state["selected_ids"] = ["A"]
prepared = GameSurfaces.build(hand_spec(%w[A B], packet: true, epoch: "2"), state: prepared_state)
assert(prepared.state["selected_ids"].empty?, "New deal restored a previously prepared packet")

# Multiple removals choose the nearest surviving predecessor.
packet = GameSurfaces.build(hand_spec(%w[A B C D E], packet: true))
packet.fields.first.index = 3
packet.update_spec(hand_spec(%w[A E], packet: true))
assert(selected(packet) == "A", "Packet removal chose a removed neighbour")

sorted = GameSurfaces.build(hand_spec(%w[B D]))
sorted.handle_command("sort_cards", "mode" => "number", "toggle" => true)
sorted.fields.first.index = 1
sorted.update_spec(hand_spec(%w[B D Z A]))
assert(sorted.fields.first.options == %w[A B D Z] && selected(sorted) == "A", "Sorted draw used highest card, not last draw")
sorted.handle_command("sort_cards", "mode" => "number", "toggle" => true)
sorted.update_spec(hand_spec(%w[B D Z A C]))
assert(sorted.fields.first.options == %w[Z D C B A] && selected(sorted) == "C", "Descending draw lost identity")
restored = GameSurfaces.build(hand_spec(%w[B D Z A C]), state: sorted.state)
assert(selected(restored) == "C" && restored.take_cursor_announcement(0) == nil, "Restoring state moved or spoke")

# Reused handlers must read new cards, not the constructor's stale array.
surface = GameSurfaces.build(hand_spec(%w[A B C]))
surface.fields.first.index = 2
surface.update_spec(hand_spec(%w[A B]))
events = []
surface.on_action { |action| events << action }
surface.fields.first.trigger(:select, [1])
assert(events.size == 1 && events.first["card_id"] == "B", "Reused control selected a stale card")

layout = GameRoomLayout::Screen.new(view_spec: layout_spec(hand_spec(%w[A B C D])), phase: :active)
form = layout.form
hand_field = layout.surface.fields.first
hand_field.index = 3
original_fields = form.fields.dup
layout.update(view_spec: layout_spec(hand_spec(%w[A B C])), history_items: [], user_items: [], users_header: "")
assert(layout.form.equal?(form) && form.fields == original_fields, "Card play replaced form fields")
assert(layout.take_cursor_announcement == "C", "Focused hand did not expose speech")
chat_index = form.fields.index(layout.chat)
form.index = chat_index
layout.chat.text = "typed text"
layout.chat.index = 5
layout.chat.check = 2
layout.update(view_spec: layout_spec(hand_spec(%w[A B C Z])), history_items: ["Other event"], user_items: [], users_header: "")
assert(form.index == chat_index && layout.chat.text == "typed text" && layout.chat.index == 5 && layout.chat.check == 2, "Hand update disturbed chat")
assert(layout.take_cursor_announcement == nil, "Card speech interrupted chat")
form.index = form.fields.index(hand_field)
assert(layout.take_cursor_announcement == nil, "Queued stale card speech after returning from chat")

# Entering/leaving a composite layout retains the same hand and its cursor.
commands = GameSurfaces::CommandPanelSpec.new(commands: [GameSurfaces::Command.new(id: "test", label: "Test", enabled: true)])
composite = GameSurfaces::CompositeSpec.new(parts: [GameSurfaces::SurfacePart.new(id: "actions", surface: commands),
  GameSurfaces::SurfacePart.new(id: "cards", surface: hand_spec(%w[A B C Z]))])
layout.update(view_spec: layout_spec(composite), history_items: [], user_items: [], users_header: "")
assert(form.fields[form.index].equal?(hand_field), "Composite transition lost hand focus")
layout.update(view_spec: layout_spec(hand_spec(%w[A B C Z])), history_items: [], user_items: [], users_header: "")
assert(layout.surface.fields.first.equal?(hand_field) && selected(layout.surface) == "Z", "Unwrapping lost hand state")

# A temporary non-hand card list must not replace the remembered hand cursor.
# UNO uses this exact transition after physically playing a Wild and before
# returning from its separate colour choice.
staged = GameRoomLayout::Screen.new(view_spec: layout_spec(hand_spec(%w[A B C D])), phase: :active)
staged.surface.fields.first.index = 2
colours = %w[red yellow green blue].map do |value|
  GameSurfaces::Card.new(id: value, label: value, value: value, choices: [], sort_keys: {})
end
colour_choice = GameSurfaces::CardTableSpec.new(zones: [GameSurfaces::CardZoneSpec.new(
  id: "colour_choice", header: "Choose a colour", cards: colours,
  hand_order: nil, hand_epoch: nil, empty_label: "No colours")])
staged.update(view_spec: layout_spec(colour_choice), history_items: [], user_items: [], users_header: "")
staged.surface.fields.first.index = 3
staged.update(view_spec: layout_spec(hand_spec(%w[A B D])), history_items: [], user_items: [], users_header: "")
assert(selected(staged.surface) == "B", "A transient colour selector lost the predecessor of the played Wild")
assert(staged.take_cursor_announcement == "B", "Returning from a colour selector did not announce the restored hand cursor")

layout.update(view_spec: layout_spec(hand_spec(%w[A B])), history_items: [], user_items: [], users_header: "", phase: :finished)
assert(layout.take_cursor_announcement == nil, "End of game spoke a hand card")

# Untagged lists used by dice/actions/promotions retain their old behaviour.
plain = GameSurfaces::CardTableSpec.new(zones: [GameSurfaces::CardZoneSpec.new(id: "dice", header: "Dice",
  cards: [GameSurfaces::Card.new(id: "1", label: "One", value: "1")])])
assert(!GameSurfaces.hand_surface?(plain) && !GameSurfaces.hand_surface?(commands), "Non-card control treated as a hand")
plain_surface = GameSurfaces.build(plain)
assert(!plain_surface.reusable_for?(plain) && plain_surface.take_cursor_announcement(0) == nil, "Changed ordinary list behaviour")
noncard_layout = GameRoomLayout::Screen.new(view_spec: layout_spec(plain), phase: :active)
old_noncard = noncard_layout.surface
noncard_layout.update(view_spec: layout_spec(commands), history_items: [], user_items: [], users_header: "")
assert(!noncard_layout.surface.equal?(old_noncard) && noncard_layout.take_cursor_announcement == nil, "Changed non-card layout speech")

# All real card-game hand specifications provide the raw received order.
[GameRoomGames::Uno.new, GameRoomGames::NinetyNine.new, GameRoomGames::Spades.new,
 GameRoomGames::Tysiac.new, GameRoomGames::Makao.new, GameRoomGames::Poker.new].each do |game|
  args = [%w[Alice Bob Carol], game.default_options]
  args << Struct.new(:unit_ids).new(args.first) if game.id == "spades"
  state = game.send(:initial_state, *args)
  hand = game.id == "uno" ? %w[R5a G1a B3a] : %w[AS JS KH]
  state[:hands] = { "Alice" => hand.dup, "Bob" => [], "Carol" => [] }
  state[:current_player] = "Alice"
  state[:phase] = game.id == "poker" ? :exchange : :playing
  state[:discard] = ["Y4a"] if game.id == "uno"
  view = GameRoomGames::Replay.new(players: state[:players], current_player: "Alice", history: [], accepted_events: [], state: state)
  spec = game.surface_spec(view, "Alice")
  assert(GameSurfaces.hand_surface?(spec), "Missing shared hand metadata in #{game.id}")
end
puts "PASS shared card cursor: play, draw, packets, sorting, duplicate cards, choices, in-place UI and non-card isolation"
