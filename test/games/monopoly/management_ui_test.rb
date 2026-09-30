require_relative "../../support/ui"
require_relative "../../../lib/game_surfaces"
require_relative "../../../games/monopoly"
require_relative "../../../lib/game_layout"

def assert(value, message)
  raise message unless value
end
game = GameRoomGames::Monopoly.new
state = game.send(:initial_state, %w[Alice Bob], game.default_options)
state[:owners].merge!(1 => "Alice", 3 => "Alice", 5 => "Alice")
snapshot = lambda do
  GameRoomGames::Replay.new(players: state[:players], current_player: state[:current_player], state: state,
    accepted_events: [], history: [], winner: state[:winner])
end
repository = Object.new
def repository.event_id(event); event["id"]; end
surface = GameSurfaces::PawnTrackSurface.new(game.surface_spec(snapshot.call, "Alice"))
assert(surface.handle_command("open_menu", "menu" => "build"), "H did not open building list")
assert(surface.cancel_pending_action?, "Escape would leave the room instead of the list")
2.times do |step|
  selected = nil
  surface.on_action { |action| selected = action }
  surface.fields.first.trigger(:select, [surface.fields.first.index])
  assert(selected && selected.name == "build", "Enter did not select a building action")
  status, plan = game.action_for(selected.to_h, snapshot.call, "Alice")
  assert(status == :ok, "Management bypasses/rejects normal action_for")
  event = { "id" => step + 1, "action" => plan.events.first.action, "value" => plan.events.first.value }
  assert(game.send(:apply_property_action, state, event, "Alice", repository, []), "Building event rejected")
  surface = GameSurfaces::PawnTrackSurface.new(game.surface_spec(snapshot.call, "Alice"), state: surface.state)
  assert(surface.state["menu"] == "build", "Build returned to Roll")
  assert(surface.fields.first.options.all? { |s| s.include?("cost:") && s.include?("buildings:") }, "Cost/count missing on refresh")
end
assert(state[:houses].values_at(1, 3) == [1, 1], "UI allowed uneven construction")
layout = GameRoomLayout::Screen.new(view_spec: game.game_view_spec(snapshot.call, "Alice"),
  history_items: [], user_items: ["Alice", "Bob"], users_header: "Players", phase: :active)
layout.focus_users
layout.surface.handle_command("open_menu", "menu" => "build")
layout.focus_game(silent: true)
assert(layout.focus_location == [:game, 0], "H from users would leave arrows on users")
assert(game.custom_game_shortcuts(snapshot.call, "Alice").find { |s| s.key == "h" && s.modifiers.empty? }.payload["focus_surface"], "H did not request the opened list's focus")
surface.cancel_pending_action!
assert(surface.fields.first.options == ["Roll the dice"], "Escape did not return to Roll")
assert(surface.handle_command("open_menu", "menu" => "mortgage"), "K did not open mortgage list")
assert(surface.fields.first.options.first.include?("receive 100"), "Mortgage amount missing")
state[:mortgaged][5] = true
surface = GameSurfaces::PawnTrackSurface.new(game.surface_spec(snapshot.call, "Alice"), state: surface.state)
assert(surface.state["menu"].empty?, "Exhausted mortgage list stayed open")
assert(surface.handle_command("open_menu", "menu" => "unmortgage"), "Shift+K did not open redemption list")
assert(surface.fields.first.options.first.include?("cost: 110"), "Redemption overcharges through floating-point rounding")
# Ownership/phase changes may never leave stale actionable property rows.
state[:current_player] = "Bob"
surface = GameSurfaces::PawnTrackSurface.new(game.surface_spec(snapshot.call, "Alice"), state: surface.state)
assert(surface.state["menu"].empty? && !surface.cancel_pending_action?, "Management remained active on another turn")
puts "Monopoly management surface: persistent lists, updated costs, even builds, Escape and turn changes passed"
