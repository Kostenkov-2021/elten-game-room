# encoding: UTF-8
require_relative "../support/tile_interaction"

checks = []
check = lambda do |name, &block|
  block.call
  checks << [name, nil]
rescue StandardError => error
  checks << [name, "#{error.class}: #{error.message}"]
end

check.call("D1: G/D only set a persistent preferred side; Enter never asks") do
  game, state, surface = domino_fixture
  actions = []
  surface.on_action { |action| actions << action }
  control = surface.fields.first
  control.trigger(:select, [0])
  assert(actions.last&.[]("target") == "r", "initial ambiguous Enter should use right")
  assert(control.header == "Your tiles" && !surface.cancel_pending_action?, "unexpected side picker")
  before = Marshal.dump(state)
  actions.clear
  control.index = 1 # This tile does not fit: a preference must not play it.
  %w[l l r l].each do |side|
    shortcut = game.custom_game_shortcuts(tile_replay(state), "Alice").find { |item| item.key == (side == "l" ? "g" : "d") }
    result = surface.handle_command(shortcut.action_name, shortcut.payload)
    assert(result == true && actions.empty?, "changing side attempted a game action")
    assert(control.index == 1, "changing side moved the hand cursor")
  end
  assert($spoken_messages.last == "Left", "missing brief side confirmation")
  assert(Marshal.dump(state) == before, "local preference mutated the shared game")
  2.times do
    control.index = 0
    control.trigger(:select, [0])
    assert(actions.last["tile"] == "121" && actions.last["target"] == "l", "preference was not applied")
    assert(game.action_for(actions.last, tile_replay(state), "Alice").first == :ok, "preferred action bypasses normal validation")
    surface.update_spec(game.surface_spec(tile_replay(state), "Alice"))
  end
  restored = GameSurfaces.build(game.surface_spec(tile_replay(state), "Alice"), state: surface.state)
  restored.on_action { |action| actions << action }
  restored.fields.first.trigger(:select, [0])
  assert(actions.last["target"] == "l", "recreating the surface lost preferred side")
end

check.call("preferred side survives table inspection, other turns and next round") do
  game, state, surface = domino_fixture
  surface.handle_command("tile_side", "target" => "l")
  surface.handle_command("tile_table")
  restored = GameSurfaces.build(game.surface_spec(tile_replay(state), "Alice"), state: surface.state)
  restored.cancel_pending_action!
  state[:current_player] = "Bob"
  restored.update_spec(game.surface_spec(tile_replay(state), "Alice"))
  assert(restored.handle_command("tile_side", "target" => "r") == true, "cannot set preference while waiting")
  restored.handle_command("tile_side", "target" => "l")
  state[:current_player] = "Alice"
  state[:round] += 1
  restored.update_spec(game.surface_spec(tile_replay(state), "Alice"))
  actions = []
  restored.on_action { |action| actions << action }
  restored.fields.first.trigger(:select, [0])
  assert(actions.last&.[]("target") == "l", "preference reset across rounds or turns")
end

check.call("only legal end overrides preference without changing it; empty chain still opens") do
  game, state, surface = domino_fixture
  surface.handle_command("tile_side", "target" => "l")
  state[:hands]["Alice"] = %w[230 121 330]
  surface.update_spec(game.surface_spec(tile_replay(state), "Alice"))
  actions = []
  surface.on_action { |action| actions << action }
  surface.fields.first.index = surface.fields.first.options.index("2–3")
  surface.fields.first.trigger(:select, [surface.fields.first.index])
  assert(actions.last&.[]("target") == "r", "left preference prevented a right-only move")
  surface.fields.first.index = surface.fields.first.options.index("1–2")
  surface.fields.first.trigger(:select, [surface.fields.first.index])
  assert(actions.last&.[]("target") == "l", "fallback overwrote preferred side")
  state[:chain] = []
  surface.update_spec(game.surface_spec(tile_replay(state), "Alice"))
  surface.fields.first.trigger(:select, [0])
  assert(game.action_for(actions.last, tile_replay(state), "Alice").first == :ok, "cannot open an empty chain")
end

check.call("D2: table cursor tracks physical tile IDs, including duplicates") do
  game, state, surface = domino_fixture
  state[:chain] << {tile: "121", left: 2, right: 1}
  state[:hands]["Alice"].delete("121")
  surface.update_spec(game.surface_spec(tile_replay(state), "Alice"))
  surface.handle_command("tile_table")
  surface.fields.first.index = 1
  saved = surface.state
  state[:chain].unshift(tile: "140", left: 4, right: 1)
  spec = game.surface_spec(tile_replay(state), "Alice")
  surface.update_spec(spec)
  restored = GameSurfaces.build(spec, state: saved)
  [surface, restored].each do |view|
    assert(view.fields.first.index == 2, "prepend selected a different physical tile")
    assert(spec.table[view.fields.first.index][:id] == "121", "identical copies lost their identities")
  end
end

check.call("T1: table inspection cancels a train destination choice safely") do
  game, state, surface = train_fixture
  control = surface.fields.first
  actions = []
  surface.on_action { |action| actions << action }
  control.trigger(:select, [0])
  assert(control.header.include?("Choose where"), "fixture has no train choice")
  surface.handle_command("tile_table")
  assert(control.header == "Trains", "C did not open the train list")
  surface.cancel_pending_action!
  assert(control.header == "Your tiles" && control.index == 0, "wrong hand cursor after C and Escape")
  assert(!surface.cancel_pending_action? && actions.empty?, "invisible pending choice or accidental action")
  control.trigger(:select, [0])
  control.trigger(:select, [1])
  assert(actions.one? && actions.first["tile"] == "6c0" && actions.first["target"] == "m", "choice uses a list index as a tile index")
end

check.call("M1: train details do not change owner after elimination and a real new deal") do
  game, state, surface = train_fixture
  surface.handle_command("tile_table")
  surface.fields.first.index = 1
  surface.fields.first.trigger(:select, [1])
  saved = surface.state
  state[:eliminated]["Bob"] = true
  game.send(:deal, state, {"seed" => "0" * 32, "time" => 1}, 1, [])
  spec = game.surface_spec(tile_replay(state), "Alice")
  surface.update_spec(spec)
  restored = GameSurfaces.build(spec, state: saved)
  [surface, restored].each do |view|
    assert(view.fields.first.header == "Your tiles" && !view.state["tile_view"], "new round reinterpreted old train details")
  end
end

check.call("train and detailed tile selections use stable IDs during the same round") do
  game, state, surface = train_fixture
  surface.handle_command("tile_table")
  surface.fields.first.index = 1
  surface.fields.first.trigger(:select, [1])
  surface.fields.first.index = 1 # Bob's 12-9, not the station.
  saved = surface.state
  state[:trains] = state[:trains].to_a.rotate.to_h
  state[:trains]["p1"][:chain] << {tile: "890", left: 9, right: 8}
  state[:trains]["p1"][:end] = 8
  spec = game.surface_spec(tile_replay(state), "Alice")
  surface.update_spec(spec)
  restored = GameSurfaces.build(spec, state: saved)
  [surface, restored].each do |view|
    assert(view.fields.first.header.start_with?("Bob,"), "row reordering changed train owner")
    assert(view.fields.first.options[view.fields.first.index] == "12–9", "append changed inspected tile")
    view.cancel_pending_action!
    assert(view.fields.first.options[view.fields.first.index].start_with?("Bob,"), "Escape selected another train")
  end
end

check.call("T2: recreated/updated table view stays silent but retains the hidden hand cursor") do
  [domino_fixture, train_fixture].each do |game, state, surface|
    surface.handle_command("tile_table")
    saved = surface.state
    state[:hands]["Alice"] << "440"
    spec = game.surface_spec(tile_replay(state), "Alice")
    surface.update_spec(spec)
    restored = GameSurfaces.build(spec, state: saved)
    [surface, restored].each do |view|
      assert(view.take_cursor_announcement(0).nil?, "table view read a hidden hand tile")
      view.cancel_pending_action!
      assert(view.fields.first.options[view.fields.first.index] == "4–4", "last drawn tile lost behind table view")
      assert(view.fields.first.last_focus_spoken == true && view.fields.first.last_focus_header == "", "return to hand did not read only the current tile")
    end
  end
end

check.call("T3: cancelling train choice reads only the tile, not the hand header") do
  _, _, surface = train_fixture
  surface.fields.first.trigger(:select, [0])
  before = $spoken_messages.length
  surface.cancel_pending_action!
  assert(surface.fields.first.last_focus_header.to_s.empty?, "repeated hand header")
  assert(surface.fields.first.last_focus_spoken == true && surface.fields.first.options[surface.fields.first.index] == "6–12", "did not focus the selected tile")
  assert($spoken_messages.length == before, "extra speech in addition to native tile focus")
end

check.call("Mexican Train retains its train picker and ignores Domino side preferences") do
  game, state, surface = train_fixture
  actions = []
  surface.on_action { |action| actions << action }
  result = surface.handle_command("tile_side", "target" => "l")
  assert(!result.is_a?(GameSurfaces::Action) && actions.empty?, "Domino shortcut generated a train move")
  surface.fields.first.trigger(:select, [0])
  assert(surface.fields.first.options.length == 4 && actions.empty?, "all trains should be shown without guessing")
  assert(game.surface_spec(tile_replay(state), "Alice").zones.first.cards.first.choices.map(&:id) == %w[p0 m p1 p2], "wrong train order")
end

checks.each { |name, error| puts "#{error ? 'FAIL' : 'PASS'} #{name}#{error ? ": #{error}" : ''}" }
abort "#{checks.count { |_, error| error }}/#{checks.length} tile interaction checks failed" if checks.any? { |_, error| error }
puts "#{checks.length} tile interaction checks passed."
