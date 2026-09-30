require_relative "../../support/ui"
require_relative "../../../lib/game_surfaces"
require_relative "../../../games/uno"

def assert(value, message)
  raise message unless value
end

game = GameRoomGames::Uno.new
state = game.send(:initial_state, %w[Alice Bob], game.default_options)
deck = game.send(:classic_deck).dup
hand = deck.reverse
state.update(phase: :playing, current_player: "Alice", colour: "R", discard: [],
  hands: { "Alice" => hand.dup, "Bob" => [] })
view = GameRoomGames::Replay.new(players: state[:players], current_player: "Alice",
  history: [], accepted_events: [], state: state)
spec = game.surface_spec(view, "Alice")
shortcuts = game.custom_game_shortcuts(view, "Alice")

# Independent expected order, including duplicate cards, not the game's sort keys.
colours = %w[Y R B G]
faces = %w[0 1 2 3 4 5 6 7 8 9 V S D]
copies = lambda { |colour, face| face == "0" ? ["#{colour}0a"] : %w[a b].map { |copy| "#{colour}#{face}#{copy}" } }
wilds = %w[NW0 NW1 NW2 NW3 NF0 NF1 NF2 NF3]
by_colour = colours.flat_map { |colour| faces.flat_map { |face| copies.call(colour, face) } } + wilds
by_number = faces.flat_map { |face| colours.flat_map { |colour| copies.call(colour, face) } } + wilds

[["c", by_colour], ["h", by_number]].each do |key, expected|
  surface = GameSurfaces::CardTable.new(spec)
  surface.fields.first.index = 7
  focused_label = surface.fields.first.options[7]
  shortcut = shortcuts.find { |item| item.key == key && item.modifiers == [:shift] }
  3.times do |press|
    assert(surface.handle_command("sort_cards", shortcut.payload), "Shift+#{key} refused")
    order = press.odd? ? expected.reverse : expected
    labels = order.map { |card| game.send(:uno_label, card, state) }
    assert(surface.fields.first.options == labels, "Wrong Shift+#{key} order on press #{press + 1}")
    assert(surface.fields.first.options[surface.fields.first.index] == focused_label, "Focus changed after sorting")
    surface = GameSurfaces::CardTable.new(spec, state: surface.state)
    assert(surface.fields.first.options == labels, "Sort order lost on refresh")
  end
  reset = shortcuts.find { |item| item.key == "d" && item.modifiers == [:shift] }
  surface.handle_command("sort_cards", reset.payload)
  assert(surface.fields.first.options == hand.map { |card| game.send(:uno_label, card, state) }, "Deal order not restored")
end

assert(state[:hands]["Alice"] == hand, "Sorting changed the actual hand")
assert(game.send(:classic_deck) == deck, "Sorting changed the deck")
assert(GameRoomGames::Uno::COLORS == %w[R Y G B], "Deck colour order changed")
assert(game.send(:available_colors, state) == %w[R Y G B], "Colour choice order changed")
assert(game.send(:all_colors).last(4) == %w[O P T U], "Dark colour order changed")
puts "PASS UNO colour/value order, both directions, refresh, focus and deal order"
