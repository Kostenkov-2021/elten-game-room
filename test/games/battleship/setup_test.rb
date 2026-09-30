require_relative "../../support/ui"
require_relative "../../../lib/game_surfaces"
require_relative "../../support/new_games_fixture"
require_relative "../../../lib/hidden_submissions"

$setup_speech = []
def speak(message, **_options)
  $setup_speech << message
end

game = GameRoomGames::Battleship.new
players = %w[Alice Bob]
repo = NewGames116Repository.new(players)
session = { "__id" => 7, "__players" => players, "options" => JSON.generate(game.default_options) }
empty = game.replay(session, [], repo)
surface = GameSurfaces.build(game.surface_spec(empty, "Alice"))
assert(surface.fields.first.is_a?(ListBox), "setup must ask before showing the grid")
assert(surface.fields.first.options == ["Randomly", "Manually"], "wrong setup choices")
assert(surface.take_cursor_announcement(nil) == nil, "setup prompt stole focus from another field")
assert(surface.take_cursor_announcement(0) == "How would you like to arrange your fleet? Randomly", "silent game start did not announce the setup question")
assert(surface.take_cursor_announcement(0) == nil, "setup prompt repeated")
assert(GameSurfaces.build(game.surface_spec(empty, "Alice"), state: surface.state).take_cursor_announcement(0) == nil,
  "setup prompt repeated after a network refresh")
selections = []
surface.on_action { |selection| selections << selection }
surface.fields.first.index = 1
surface.fields.first.trigger(:select)
assert(selections.map { |selection| [selection.kind, selection.name] } == [["surface", "refresh"]], "manual setup wrote a game event")
assert(surface.fields.first.is_a?(GridBox), "manual setup did not open the board")
manual = GameSurfaces.build(game.surface_spec(empty, "Alice"), state: surface.state)
assert(manual.fields.first.is_a?(GridBox), "refresh asked for setup again")
manual.fields.first.trigger(:select, [0, 0])
manual.fields.first.trigger(:select, [3, 0])
manual.fields.first.trigger(:select, [0, 2])
retained = GameSurfaces.build(game.surface_spec(empty, "Alice"), state: manual.state)
assert(retained.state["ships"] == [[0,1,2,3]] && retained.state["bow"] == 20, "refresh lost a manual draft")
retained.handle_command("undo")
assert(retained.state["ships"].length == 1 && retained.state["bow"] == -1, "cancel bow removed a ship")
retained.handle_command("undo")
assert(retained.state["ships"].empty?, "manual undo failed")
assert(GameSurfaces.build(game.surface_spec(empty, "Alice")).fields.first.is_a?(ListBox), "new game inherited manual choice")
assert(GameSurfaces.build(game.surface_spec(empty, "Bob"), state: manual.state).fields.first.is_a?(ListBox), "another player inherited placement")

%w[polish classic].each_with_index do |fleet, number|
  [false, true].each do |touching|
    local_session = session.merge("options" => JSON.generate(game.normalize_options("fleet" => fleet, "touching" => touching)))
    replay = game.replay(local_session, [], repo)
    vault = HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new)
    context = GameRoomGames::ActionContext.new(session_id: 7 + number, hidden_submissions: vault)
    chooser = GameSurfaces.build(game.surface_spec(replay, "Alice"))
    selection = nil
    chooser.on_action { |action| selection = action }
    chooser.fields.first.trigger(:select)
    assert(selection.name == "random_fleet", "random choice did not activate")
    assert(chooser.state["setup_mode"] == "random", "random choice was not remembered locally")
    status, plan = game.action_for(selection, replay, "Alice", context: context)
    assert(status == :ok && plan.events.length == 1, "random choice did not seal the fleet")
    event = plan.events.first
    assert(event.action == "place" && event.value.match?(/\A[0-9a-f]{64}\z/), "random setup exposed ships")
    envelope = vault.reveal(session_id: context.session_id, round_id: "fleet", user: "Alice")
    assert(game.legal_fleet?(replay.state, envelope.payload["ships"]), "random fleet violates selected rules")
    status, retry_plan = game.action_for(selection, replay, "Alice", context: context)
    assert(status == :ok && retry_plan.events.first.value == event.value, "retry changed a pending fleet")
    sealed = game.replay(local_session, [{ "id" => 1, "actor" => "Alice", "action" => "place", "value" => event.value }], repo)
    accepted_event = sealed.accepted_events.first
    assert(game.describe_event_for_display(accepted_event, repo, sealed, "Alice", surface_state: chooser.state) == ["Your ships have been placed automatically."],
      "accepted random placement has no confirmation")
    assert(game.describe_event_for_display(accepted_event, repo, sealed, "Bob", surface_state: chooser.state) == ["Alice sealed the fleet."],
      "another player's fleet was announced as the viewer's")
    assert(game.describe_event_for_display(accepted_event, repo, sealed, "Alice", surface_state: {"setup_mode" => "manual"}) == ["Alice sealed the fleet."],
      "manual placement was announced as random")
    assert(!game.surface_spec(sealed, "Alice").is_a?(GameSurfaces::FleetGridSpec), "sealed player was asked again")
    assert(game.action_for(selection, sealed, "Alice", context: context).first == :invalid, "sealed fleet can be replaced")
    assert(game.action_for(selection, replay, "Observer", context: context).first == :invalid, "observer can place ships")
    assert(game.action_for({ "action" => "seal" }, replay, "Alice", context: context).first == :not_ready, "empty manual placement silently became random")
  end
end

storage = HiddenSubmissions::MemoryStorage.new
storage.define_singleton_method(:update) { |&_block| raise HiddenSubmissions::StorageError, "unavailable" }
context = GameRoomGames::ActionContext.new(session_id: 77, hidden_submissions: HiddenSubmissions::Vault.new(storage))
assert(game.action_for({ "action" => "random_fleet" }, empty, "Alice", context: context).first == :local_storage_unavailable,
  "failed local save was treated as a sealed fleet")
puts "PASS Battleship setup: random/manual, draft persistence, four rule combinations, retry, privacy and storage failure"
