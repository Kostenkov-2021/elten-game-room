require_relative "../../support/sequence_random"

require_relative "../../support/rules_live_help"

game = GameRoomGames::CatHeadTail.new
repository = Object.new
def repository.players_for(_session); %w[Alice Bob]; end
def repository.actor_of(event, _session); event.fetch("actor"); end
def repository.event_id(event); event.fetch("id"); end
session = { "options" => JSON.generate(game.default_options) }
events = [{ "id" => 1, "actor" => "Alice", "action" => "roll", "value" => "8|minus" }]
replay = game.replay(session, events, repository)
layout = GameRoomLayout::Screen.new(view_spec: game.game_view_spec(replay, "Alice"),
  chat_text: "draft stays", chat_index: 3, chat_check: 7,
  history_items: ["Earlier event"], user_items: %w[Alice Bob])
screen = GameScreen.allocate
screen.instance_variable_set(:@game, game)
screen.instance_variable_set(:@session, session)
screen.instance_variable_set(:@layout, layout)
shortcuts = game.game_shortcuts(replay, "Alice")
screen.send(:bind_game_shortcuts, layout.form, layout.shortcut_fields, shortcuts) { raise "Help submitted a move" }
GameRoomContextHelp.replace([layout.chat], ["CHAT-ONLY"], source: :game)
expected = GameRoomContextHelp.game_field_tips(layout.game_help_fields)
assert(expected.any? { |text| text.start_with?("D,") }, "D did not reach the actual game-field help")
assert(expected.uniq == expected && !expected.include?("CHAT-ONLY"), "help duplicates or chat tips leaked")
before = Marshal.dump([replay.state, layout.surface.state, layout.form.index,
  layout.chat.text, layout.chat.index, layout.chat.check])
assert(read_live_shortcuts(screen, replay) == expected, "rules shortcuts disagree with game-field F1")
$spoken_messages.clear
assert(screen.send(:activate_game_shortcut, shortcuts.find { |item| item.key == "d" }) == nil, "D became an action")
assert($spoken_messages == ["Alice, 8, -8 points."], "D did not speak one concise message")
after = Marshal.dump([replay.state, layout.surface.state, layout.form.index,
  layout.chat.text, layout.chat.index, layout.chat.check])
assert(before == after, "read-only help/D changed state, focus or draft")
assert(shortcuts.none? { |item| item.key == "z" }, "dice actions were treated as a hand of cards")

surface = layout.surface
submitted = []
surface.on_action { |action| submitted << action }
surface.fields.first.trigger(:select, [0])
surface.fields.first.trigger(:select, [1])
assert(submitted.map { |action| action["card"] } == %w[roll bank], "Enter did not select the intended action")
context = GameRoomGames::ActionContext.new(random_source: GameRoomRandom::SequenceSource.new([8, 2]))
status, roll = game.action_for(submitted.first, replay, "Alice", context: context)
assert(status == :ok && roll.events.first.value == "8|plus", "real Roll control bypassed the dice source")
status, bank = game.action_for(submitted.last, replay, "Alice", context: context)
assert(status == :ok && bank.events.first.action == "bank", "real Bank control cannot bank a negative total")
assert(surface.state.fetch("hand_cursors", {}).empty?, "dice actions use the hand cursor mechanism")
puts "PASS Cat, head, tail UI: real shared surface actions, negative bank, D, live F1/rules agreement, preserved chat/focus and no card-hand shortcuts"
