require_relative "../support/rules_live_help"

# Open Ctrl+F1 through GameScreen, with the same real game/surface bindings
# that feed F1. Only the host's modal event loop is driven by a test double.

[GameRoomGames::Makao.new, GameRoomGames::Poker.new].each do |game|
  state = game.send(:initial_state, %w[Alice Bob], game.default_options)
  state.update(hands: { "Alice" => %w[9H 9S AS], "Bob" => %w[2S] },
    current_player: "Alice", phase: game.id == "poker" ? :exchange : :playing)
  state[:discard] = ["8H"] if game.id == "makao"
  replay = GameRoomGames::Replay.new(players: state[:players], current_player: "Alice", state: state, history: [], accepted_events: [])
  layout = GameRoomLayout::Screen.new(view_spec: game.game_view_spec(replay, "Alice"),
    chat_text: "niezgubiony szkic", chat_index: 5, chat_check: 9,
    history_items: ["Saved history"], user_items: %w[Alice Bob])
  screen = GameScreen.allocate
  screen.instance_variable_set(:@game, game)
  screen.instance_variable_set(:@session, { "options" => JSON.generate(game.default_options) })
  screen.instance_variable_set(:@layout, layout)
  calls = 0
  screen.send(:bind_game_shortcuts, layout.form, layout.shortcut_fields, game.game_shortcuts(replay, "Alice")) { calls += 1 }
  GameRoomContextHelp.replace(layout.shortcut_fields, ["Invite online", "Room settings"], source: :context)
  GameRoomContextHelp.replace([layout.chat], ["CHAT-ONLY"], source: :game)
  GameRoomContextHelp.replace([layout.history], ["HISTORY-ONLY"], source: :game)
  GameRoomContextHelp.replace([layout.users], ["USERS-ONLY"], source: :game)
  game_fields = layout.game_help_fields
  assert(!game_fields.empty? && (game_fields & [layout.chat, layout.history, layout.users]).empty?, "game-help field selection leaks other sections")
  expected = GameRoomContextHelp.game_field_tips(game_fields)
  expected_packet = game.id == "makao" ?
    "Press Shift+Enter to add or remove the current card from the prepared packet." :
    "Press Shift+Enter to select or unselect the current card for exchange."
  assert(expected.count(expected_packet) == 1, "actual game field lost native packet help")
  assert((expected & ["Invite online", "Room settings", "CHAT-ONLY", "HISTORY-ONLY", "USERS-ONLY"]).empty?, "non-game tips leak into game shortcuts")
  assert(expected.uniq == expected, "duplicate game shortcuts")
  before = Marshal.dump([state, layout.surface.state, layout.form.index,
    layout.chat.text, layout.chat.index, layout.chat.check, layout.history.index])
  [:enter, :escape].each do |key|
    assert(read_live_shortcuts(screen, replay, close_with: key) == expected, "rules shortcut list disagrees with F1 game-field definitions")
  end
  after = Marshal.dump([state, layout.surface.state, layout.form.index,
    layout.chat.text, layout.chat.index, layout.chat.check, layout.history.index])
  assert(before == after && calls == 0, "reading help changed hand/chat/cursor or submitted an action")

  # Rebinding after a phase change must not keep old action descriptions.
  old_bound = game_fields.flat_map { |field| field.game_room_game_help_tips.to_a }.uniq
  GameRoomContextHelp.replace(game_fields, ["New phase action"], source: :game)
  changed = read_live_shortcuts(screen, replay)
  assert(changed.include?("New phase action") && changed.include?(expected_packet), "rebinding lost current or native help")
  assert((changed & old_bound).empty?, "stale binding retained")
end

# No game fields means no live shortcuts, not an unrelated static list.
book = GameRoomGames::Makao.new.rule_book(options: {})
empty = GameRoomScreens::GameRules.new(book, game_shortcuts: [])
documents = empty.instance_variable_get(:@documents)
assert(documents[1].paragraphs == ["No shortcuts are available on this screen."], "empty live help fell back to stale controls")
assert(documents[0].text == book.documents[0].text && documents[2].text == book.documents[2].text, "live help changed rules or settings")

# A game tip equal to a room tip still belongs to the game. Normalize
# binary non-ASCII labels before deduplication, without changing host data.
field = FakeControl.new
field.define_singleton_method(:get_tips) { ["Żółta karta".b, "Native action"] }
GameRoomContextHelp.replace([field], ["Żółta karta"], source: :game)
GameRoomContextHelp.replace([field], ["Żółta karta", "Room-only"], source: :context)
tips = GameRoomContextHelp.game_field_tips([field])
assert(tips == ["Żółta karta", "Native action"], "same game/context text or encoding broke help filtering")
assert((tips.first + " — справка").valid_encoding?, "game help cannot join a non-English host label")
puts "PASS live rules help: shared F1 definitions, Makao/Poker packet help, phase replacement, Enter/Escape, isolation and preserved hand/chat/cursor"
