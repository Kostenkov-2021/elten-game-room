require_relative "../support/ui"
require_relative "../../lib/game_surfaces"
require_relative "../../games/domino"
require_relative "../../games/mexican_train"
def assert(value, message); raise message unless value; end

game = GameRoomGames::Domino.new
s = game.initial_state(%w[A B], game.default_options)
s.merge!(phase: :playing, round: 1, turn: 1, current_player: "A", hands: { "A" => %w[110 120 240], "B" => %w[330] }, chain: [{ tile: "240", left: 2, right: 4 }])
r = GameRoomGames::Replay.new(players: s[:players], state: s, current_player: "A", history: [])
spec = game.surface_spec(r, "A")
surface = GameSurfaces.build(spec)
assert(GameSurfaces.hand_surface?(spec), "explicit tile hand registration")
assert(!spec.is_a?(GameSurfaces::CardTableSpec), "tiles presented as ordinary cards")
control = surface.fields.first
actions = []
surface.on_action { |a| actions << a }
control.index = 1
control.trigger(:select, [1])
assert(actions.length == 1 && actions.first.kind == "tile" && actions.first["tile"] == "120", "single destination Enter")
control.index = 2
control.trigger(:select, [2])
assert(actions.length == 2 && actions.last["tile"] == "240" && actions.last["target"] == "r", "ambiguous Enter did not use the preferred side")
assert(!surface.cancel_pending_action? && control.index == 2 && control.header == "Your tiles", "ambiguous Enter opened a picker or moved the cursor")
surface.handle_command("tile_table")
assert(control.header == "Domino chain" && control.options == ["2–4"], "table view")
control.trigger(:select, [0])
assert($spoken_messages.last == "2–4", "table read")
saved = surface.state
assert(saved["zones"]["tiles"] == 2, "table index overwrote hand")
surface.update_spec(game.surface_spec(r, "A"))
assert(surface.fields.first.equal?(control) && control.header == "Domino chain", "refresh rebuilt/lost view")
surface.cancel_pending_action!
assert(control.index == 2, "close view moved hand")
s[:hands]["A"].delete("240")
surface.update_spec(game.surface_spec(r, "A"))
assert(control.index == 1 && surface.take_cursor_announcement(0) == "1–2", "play cursor")
s[:hands]["A"] += %w[550 660]
surface.update_spec(game.surface_spec(r, "A"))
assert(control.index == 3 && surface.take_cursor_announcement(0) == "6–6", "last drawn cursor")
assert(control.last_focus_header != "Your tiles", "extra hand caption")
shortcut = game.custom_game_shortcuts(r, "A").find { |k| k.key == "z" && k.modifiers.empty? }
action = surface.handle_command(shortcut.action_name, shortcut.payload)
assert(action.is_a?(GameSurfaces::Action) && action["tile"] == "120", "Z did not play sole legal action")
s[:hands]["A"] = %w[240 660]
surface.update_spec(game.surface_spec(r, "A"))
shortcut = game.custom_game_shortcuts(r, "A").find { |k| k.key == "z" && k.modifiers.empty? }
action = surface.handle_command(shortcut.action_name, shortcut.payload)
assert(action == true && control.options[control.index] == "2–4", "Z guessed an end")
assert(control.last_focus_spoken == true && control.last_focus_header == "", "Z repeated hand caption")
assert(game.playable_card_navigation(r, "A").nil?, "tile adapter enabled card navigation")
assert(game.surface_spec(r, "A").zones.first.hand_epoch != game.surface_spec(r, "B").zones.first.hand_epoch, "hand epoch omits its owner")

trains = GameRoomGames::MexicanTrain.new
ts = trains.initial_state(%w[A B], trains.default_options)
ts.merge!(phase: :playing, round: 1, turn: 1, current_player: "A", hands: { "A" => %w[110 120], "B" => %w[330] },
  station: 12, trains: { "p0" => { owner: "A", open: false, end: 6, chain: [{ tile: "6c0", left: 12, right: 6 }] },
    "p1" => { owner: "B", open: false, end: 12, chain: [] }, "m" => { owner: nil, open: true, end: 12, chain: [] } })
tr = GameRoomGames::Replay.new(players: ts[:players], state: ts, current_player: "A", history: [])
view = GameSurfaces.build(trains.surface_spec(tr, "A"))
tc = view.fields.first
tc.index = 1
view.handle_command("tile_table")
tc.trigger(:select, [0])
assert(view.state["tile_detail"] == 0, "train Enter did not open its tiles")
detail_options = tc.options.dup
view.update_spec(trains.surface_spec(tr, "A"))
assert(tc.equal?(view.fields.first) && tc.options == detail_options, "refresh lost train details")
restored = GameSurfaces.build(trains.surface_spec(tr, "A"), state: view.state)
assert(restored.fields.first.options == detail_options, "restoring surface lost train details")
view.handle_command("tile_table")
assert(view.state["tile_detail"].nil?, "C retained stale detail mode")
tc.trigger(:select, [1])
assert(view.state["tile_detail"] == 1, "C then Enter did not open another train")
view.cancel_pending_action!
assert(tc.index == 1 && view.state["tile_detail"].nil?, "Escape did not return to selected train")
view.cancel_pending_action!
assert(tc.header == "Your tiles" && tc.index == 1, "closing train view moved hand")
puts "Explicit tile hand: Enter, ends, views, reuse, cursor and Z: OK"
