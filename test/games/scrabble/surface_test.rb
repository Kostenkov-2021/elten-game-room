require_relative "../../support/ui"
require_relative "../../support/word_picker"
require_relative "../../../lib/game_surfaces"
require_relative "../../../games/scrabble"
def assert(value,message); raise message unless value; end
def n_(a,b,n); n == 1 ? a : b; end
game = GameRoomGames::Scrabble.new
state = game.initial_state(%w[Alice Bob],game.normalize_options("content_language_id" => "en"))
tiles = game.tiles(state)
ids = %w[c a t].map { |l| tiles.index { |t| t[:letter] == l } }
state.merge!(phase: :playing,current_player: "Alice",turn: 1,revision: 1,racks: {"Alice"=>ids,"Bob"=>[]})
replay = GameRoomGames::Replay.new(players: state[:players], current_player: "Alice", state: state,history: [])
surface = GameSurfaces.build(game.surface_spec(replay,"Alice"))
surface.fields.first.set_logical_position(6,7)
ids.each_with_index { |id, index| pick_word_tile(surface, id, 111 + index) }
assert(surface.state["draft"].length == 3, "typed draft")
assert(state[:board].compact.empty?, "draft leaked into shared state")
assert(surface.save_game_error, "draft save guard")
action = surface.handle_command("word_submit")
assert(action.name == 'place' && action['placements'].length == 3, "atomic submission")
surface.update_spec(game.surface_spec(replay,"Alice"))
assert(surface.state["draft"].length == 3, "refresh lost draft")
surface.handle_command("word_preview")
assert($spoken_messages.last.include?('10'), "point preview")
surface.handle_command("word_sort")
assert(surface.state["draft"].length == 3, "sort destroyed draft")
surface.handle_command("word_remove")
assert(surface.state["draft"].length == 2, "undo")
restored = GameSurfaces.build(game.surface_spec(replay,"Alice"),state: surface.state)
assert(restored.state["draft"] == surface.state["draft"], "resume draft")
state[:revision] = 2
surface.update_spec(game.surface_spec(replay,"Alice"))
assert(surface.state["draft"].empty?, "confirmed invalid attempt kept draft")
observer = GameSurfaces.build(game.surface_spec(replay,"Observer"))
assert(observer.state["order"].empty? && observer.handle_command("word_submit") == true, "observer cannot see rack or play")
assert(!GameSurfaces.hand_surface?(game.surface_spec(replay,"Alice")), "word rack is not a card hand")
puts "Scrabble surface passed."
