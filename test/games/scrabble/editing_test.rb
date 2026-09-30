# encoding: UTF-8
require_relative "../../support/ui"
require_relative "../../support/elten_array_shuffle"
require_relative "../../support/word_picker"
require_relative "../../../lib/game_surfaces"
require_relative "../../../games/scrabble"

def assert(value, message); raise message unless value; end
def editing_fixture
  game = GameRoomGames::Scrabble.new
  state = game.initial_state(%w[Alice Bob], game.normalize_options("content_language_id" => "en"))
  tiles = game.tiles(state)
  ids = %w[c a t].map { |letter| tiles.index { |tile| tile[:letter] == letter } }
  state.merge!(phase: :playing, current_player: "Alice", turn: 1, revision: 1, racks: {"Alice" => ids, "Bob" => []})
  replay = GameRoomGames::Replay.new(players: state[:players], current_player: "Alice", state: state, history: [])
  [game, state, replay, GameSurfaces.build(game.surface_spec(replay, "Alice"))]
end

[1, 15].each do |step|
  game, state, replay, surface = editing_fixture
  before = Marshal.dump(state)
  state[:racks]["Alice"].each_with_index do |id, index|
    pos = 112 - step + step * index
    pick_word_tile(surface, id, pos)
    assert(surface.fields.first.y * 15 + surface.fields.first.x == pos, "placement moved cursor")
  end
  expected = surface.state["draft"].map(&:dup)
  surface.fields.first.set_logical_position(7, 7)
  surface.handle_command("word_remove")
  assert(surface.state["draft"].map { |p| p[1] } == [112-step, 112+step], "Backspace removed last instead of current tile")
  assert($spoken_messages.last.start_with?("H8, empty"), "removal did not read field")
  surface.update_spec(game.surface_spec(replay, "Alice"))
  restored = GameSurfaces.build(game.surface_spec(replay, "Alice"), state: surface.state)
  pick_word_tile(restored, expected[1][0], 112)
  assert(game.preview(state, restored.state["draft"]).error.nil?, "replacement left a gap")
  assert(Marshal.dump(state) == before, "draft changed shared game")
end
game, state, replay, surface = editing_fixture
c, a, t = state[:racks]["Alice"]
state[:board][112] = {id: a, letter: "a", points: 1, blank: false}
state[:racks]["Alice"].delete(a)
surface.update_spec(game.surface_spec(replay, "Alice"))
pick_word_tile(surface, c, 111)
surface.fields.first.set_logical_position(7, 7)
surface.handle_command("word_remove")
surface.fields.first.trigger(:select)
assert(surface.state["draft"].length == 1 && state[:board][112], "committed tile removed")
surface.fields.first.set_logical_position(8, 7)
WordPickerTest.answers << nil
surface.fields.first.trigger(:select)
assert(surface.state["draft"].length == 1, "Escape lost draft")
pick_word_tile(surface, t, 113)
assert(game.preview(state, surface.state["draft"]).error.nil?, "extension around committed A invalid")

game, state, replay, _ = editing_fixture
tiles = game.tiles(state)
blank = tiles.index { |tile| tile[:letter].empty? }
copies = tiles.each_index.select { |i| tiles[i][:letter] == "a" }.first(2)
state[:racks]["Alice"] = [blank, *copies]
surface = GameSurfaces.build(game.surface_spec(replay, "Alice"))
WordPickerTest.answers.concat([0, nil])
surface.fields.first.trigger(:select)
assert(surface.state["draft"].empty?, "cancelled blank placed")
pick_word_tile(surface, blank, 224, blank: game.language(state).alphabet.index("t"))
assert(surface.state["draft"] == [[blank, 224, "t"]], "blank substitution lost")
assert(surface.fields.first.cells[14][14].include?("blank"), "blank identity hidden")
surface.handle_command("word_remove")
assert(surface.state["draft"].empty? && surface.state["order"] == [blank, *copies], "blank lost")
copies.each_with_index { |id, i| pick_word_tile(surface, id, 112+i) }
assert(surface.state["draft"].map(&:first) == copies, "duplicate tiles collapsed")
surface.handle_command("word_cancel")
surface.handle_command("word_sort")
before = surface.state
(0..6).each { |slot| surface.handle_command("word_read", "slot" => slot) }
assert(surface.state == before, "number key changed cursor or rack")
assert($spoken_messages.last == "Empty rack position.", "empty number slot")
shortcuts = game.game_shortcuts(replay, "Alice")
assert(shortcuts.none? { |s| %w[h v n delete].include?(s.key) || s.payload["command"].to_s.match?(/word_(letter|slot|undo)/) }, "obsolete controls in help")
assert(shortcuts.find { |s| s.key == "backspace" }.action_name == "word_remove", "Backspace binding")
%w[word_horizontal word_vertical word_navigate word_letter word_slot word_undo].each do |cmd|
  assert(surface.handle_command(cmd) == false, "obsolete command still accepted")
end

game, state, replay, surface = editing_fixture
WordPickerTest.answers << ->(form) {
  state[:revision] += 1
  surface.update_spec(game.surface_spec(replay, "Alice"))
  form.accept_button.trigger(:press)
}
surface.fields.first.trigger(:select)
assert(surface.state["draft"].empty?, "stale tile picker placed")
state[:racks]["Alice"] = [blank]
surface.update_spec(game.surface_spec(replay, "Alice"))
WordPickerTest.answers.concat([0, ->(form) {
  state[:revision] += 1
  surface.update_spec(game.surface_spec(replay, "Alice"))
  form.accept_button.trigger(:press)
}])
surface.fields.first.trigger(:select)
assert(surface.state["draft"].empty?, "stale blank picker placed")

game, state, replay, surface = editing_fixture
pick_word_tile(surface, state[:racks]["Alice"].first, 112)
state[:bag] = Array.new(8, 99)
surface.update_spec(game.surface_spec(replay, "Alice"))
WordPickerTest.answers << 1
surface.handle_command("word_pass")
assert(surface.state["draft"].length == 1, "No discarded draft")
WordPickerTest.answers.concat([0, nil])
surface.handle_command("word_exchange")
assert(surface.state["draft"].length == 1, "cancelled exchange discarded draft")
WordPickerTest.answers.concat([0, [0, 2]])
result = surface.handle_command("word_exchange")
assert(result.name == "exchange" && result["tiles"] == state[:racks]["Alice"].values_at(0, 2), "wrong exchange")
assert(surface.state["draft"].empty?, "confirmed exchange retained draft")
surface.handle_command("word_submit")
assert($spoken_messages.last == "Place at least one tile to form or extend a word.", "misleading empty draft")
assert(WordPickerTest.answers.empty?, "unused picker answers")
puts "Scrabble simplified interface: placement, removal, modal refresh, blank, cancel, numbers, help and exchange passed."
