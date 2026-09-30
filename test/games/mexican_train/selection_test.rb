# encoding: UTF-8
require_relative "../../support/tile_interaction"
game, state, surface = train_fixture
actions = []
surface.on_action { |action| actions << action }
control = surface.fields.first
control.trigger(:select, [0])
assert(control.options == ["Alice, 12", "Mexican train, 12", "Bob, 9", "Carol, 3"], "missing trains/order")
control.index = 2
control.trigger(:select, [2])
assert($spoken_messages.last == "Bob's train is closed." && actions.empty? && surface.cancel_pending_action?, "closed target not explained/kept")
# Updates preserve the chosen train by ID even when other train rows reorder.
state[:trains] = state[:trains].to_a.reverse.to_h
surface.update_spec(game.surface_spec(tile_replay(state), "Alice"))
assert(control.options[control.index] == "Bob, 9", "refresh changed selected target")
state[:trains]["p1"][:open] = true
surface.update_spec(game.surface_spec(tile_replay(state), "Alice"))
control.trigger(:select, [control.index])
assert($spoken_messages.last == "This tile does not fit this train." && actions.empty?, "mismatch not explained")
surface.cancel_pending_action!
control.index = 2
control.trigger(:select, [2])
assert(!surface.cancel_pending_action? && $spoken_messages.last == "This tile does not fit any train.", "dead tile opened list")
# One legal tile, one legal target: Z only navigates and Enter still offers every train.
state[:hands]["Alice"] = %w[6c0 550]
state[:trains]["m"][:end] = 7
surface.update_spec(game.surface_spec(tile_replay(state), "Alice"))
shortcut = game.custom_game_shortcuts(tile_replay(state), "Alice").find { |s| s.key == "z" && s.modifiers.empty? }
assert(shortcut.payload["card_ids"] == ["6c0"], "visible invalid targets counted as playable")
result = surface.handle_command(shortcut.action_name, shortcut.payload)
assert(result == true && actions.empty? && control.options[control.index] == "6–12", "Z auto-played/selected invalid tile")
control.trigger(:select, [control.index])
assert(control.options.length == 4 && actions.empty?, "sole destination auto-played")
control.trigger(:select, [0])
assert(actions.length == 1 && actions.last["target"] == "p0", "valid destination did not emit standard move")
assert(game.action_for(actions.last, tile_replay(state), "Alice").first == :ok, "normal action rejected")

# Required closed train takes priority; the next player cannot bypass it.
state[:trains]["p1"][:open] = false
state[:pending] = ["p1"]
state[:hands]["Alice"] = %w[590 6c0]
surface.update_spec(game.surface_spec(tile_replay(state), "Alice"))
index = control.options.index("6–12")
control.trigger(:select, [index])
assert($spoken_messages.last == "You must cover double 9 on Bob's train. This tile does not fit.", "no-destination obligation missing")
index = control.options.index("5–9")
control.trigger(:select, [index])
control.trigger(:select, [0])
assert($spoken_messages.last == "You must cover double 9 on Bob's train." && actions.length == 1, "wrong obligation priority")
index = control.options.index("Bob, 9")
control.trigger(:select, [index])
assert(actions.last["target"] == "p1" && game.action_for(actions.last, tile_replay(state), "Alice").first == :ok, "required closed target rejected")

# The author of a double series may cover an older double.
state[:series] = true
state[:pending] = ["p0", "m"]
state[:trains]["p0"][:end] = 6
state[:trains]["m"][:end] = 9
state[:hands]["Alice"] = %w[460 550]
surface.update_spec(game.surface_spec(tile_replay(state), "Alice"))
control.trigger(:select, [control.options.index("4–6")])
control.trigger(:select, [0])
assert(actions.last["target"] == "p0" && game.action_for(actions.last, tile_replay(state), "Alice").first == :ok, "older-double exception lost")
# Losing the turn while the picker is open rejects without a network action.
surface.update_spec(game.surface_spec(tile_replay(state), "Alice"))
control.trigger(:select, [control.options.index("4–6")])
state[:current_player] = "Bob"
surface.update_spec(game.surface_spec(tile_replay(state), "Alice"))
count = actions.length
control.trigger(:select, [0])
assert(actions.length == count && $spoken_messages.last == "This move is not available.", "stale picker sent a move")
surface.cancel_pending_action!
assert(control.last_focus_header == "" && control.options[control.index] == "4–6", "cancel lost tile/header")
puts "Mexican Train all-target selection, reasons, refresh, Z and double-series regression passed."
