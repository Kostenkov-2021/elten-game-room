require_relative "../../support/new_games_fixture"

def uno_wild_state(game, card, options = {})
  players = %w[Alice Bob Carol]
  state = game.send(:initial_state, players, game.normalize_options({
    "thinking_time" => 30,
    "interceptions" => true,
    "bluff_challenge" => true
  }.merge(options)))
  state.update(
    phase: :playing,
    round: 1,
    current_player: "Alice",
    discard: ["R5a"],
    colour: "R",
    turn_deadline: 1_800_000_030,
    hands: {
      "Alice" => [card, "R7a", "G2a"],
      "Bob" => %w[R5b B3a],
      "Carol" => %w[Y4a G6a]
    }
  )
  state
end

def uno_wild_replay(state, history = [])
  GameRoomGames::Replay.new(
    players: state[:players], current_player: state[:current_player], winner: state[:winner],
    draw: false, accepted_events: [], history: history, state: state
  )
end

def apply_uno_event(game, state, action, value, actor, id)
  event = { "id" => id, "actor" => actor, "action" => action, "value" => value }
  history = []
  repository = NewGames116Repository.new(state[:players])
  applied = case action
  when "play" then game.send(:apply_play, state, event, actor, repository, history)
  when "choose_colour" then game.send(:apply_choose_colour, state, event, actor, repository, history)
  else false
  end
  [applied, history, event]
end

game = GameRoomGames::Uno.new

state = uno_wild_state(game, "NW0")
replay = uno_wild_replay(state)
surface = game.surface_spec(replay, "Alice")
wild = surface.zones.first.cards.find { |card| card.id == "NW0" }
assert(wild != nil && wild.choices.to_a.empty?, "Wild still asks for a colour before it is played")

status, plan = game.action_for(
  { "kind" => "card", "action" => "select", "card_id" => "NW0", "card" => "NW0" },
  replay, "Alice", context: context_for
)
assert(status == :ok && plan.events.length == 1, "Wild did not create one physical play event")
assert(plan.events.first.action == "play" && plan.events.first.value == "NW0||0",
  "Wild included the colour or a running deadline in its play event")

applied, play_history, = apply_uno_event(game, state, "play", plan.events.first.value, "Alice", 1)
assert(applied, "The physical Wild play was rejected")
assert(state[:discard].last == "NW0" && !state[:hands]["Alice"].include?("NW0"),
  "Wild was not physically moved to the discard pile")
assert(state[:colour] == nil && state[:turn_deadline] == 0 && state[:current_player] == "Alice",
  "Colour selection did not pause the turn and its clock")
assert(play_history.map(&:text) == ["Alice played wild."],
  "The first event announced more than the physical Wild play")

pending = uno_wild_replay(state, play_history)
spoken = game.describe_event({ "id" => 1, "actor" => "Alice", "action" => "play", "value" => "NW0||0" },
  NewGames116Repository.new(state[:players]), pending, "Alice")
assert(spoken == ["Alice played wild.", "Choose a colour."],
  "The Wild player was not prompted to choose a colour after the physical play")
observer_spoken = game.describe_event({ "id" => 1, "actor" => "Alice", "action" => "play", "value" => "NW0||0" },
  NewGames116Repository.new(state[:players]), pending, "Bob")
assert(observer_spoken == ["Alice played wild."],
  "Another player received the Wild owner's colour prompt")
assert(game.active_actors(pending) == ["Alice"], "Another player can act while the colour is being selected")
assert(game.legal_actions(pending, "Bob").empty?, "Another player can intercept while colour selection is open")
assert(!game.automatic_action_due?(pending, "Alice", context: GameRoomGames::ActionContext.new(now: 1_900_000_000)),
  "Thinking time kept running during colour selection")
assert(game.bot_move_delay(pending, "Alice", context: context_for) == 0.0,
  "A bot waits for a second move delay before selecting a colour")

choice_surface = game.surface_spec(pending, "Alice")
assert(choice_surface.zones.first.id == "colour_choice", "The colour selector did not replace the hand")
assert(choice_surface.zones.first.cards.map(&:id) == %w[Y R B G],
  "The Wild colour selector is not ordered yellow, red, blue, green")

status, colour_plan = game.action_for(
  { "kind" => "card", "action" => "select", "card_id" => "G", "card" => "G" },
  pending, "Alice", context: context_for
)
assert(status == :ok && colour_plan.events.first.action == "choose_colour",
  "Selecting a colour did not create a separate event")
assert(colour_plan.events.first.value == "G|1800000030",
  "The next player did not receive a fresh thinking-time deadline")

applied, colour_history, = apply_uno_event(game, state, "choose_colour", colour_plan.events.first.value, "Alice", 2)
assert(applied && state[:colour] == "G" && state[:current_player] == "Bob",
  "The separate colour choice did not complete the turn")
assert(state[:turn_deadline] == 1_800_000_030 && !game.send(:colour_choice_pending?, state),
  "The deadline or pending colour state was not restored after the choice")
assert(colour_history.map(&:text) == ["Alice chose green."],
  "The second event did not announce only the selected colour")

state = uno_wild_state(game, "NF0")
state[:hands]["Alice"] = %w[NF0 G2a]
applied, history, = apply_uno_event(game, state, "play", "NF0||0", "Alice", 10)
assert(applied && state[:pending_draw] == 4 && state[:challenge_player] == nil,
  "Wild Draw Four did not stage its penalty before colour selection")
assert(history.map(&:text) == ["Alice played wild draw four."],
  "Wild Draw Four exposed its colour in the physical play event")
draw_four_pending = uno_wild_replay(state, history)
draw_four_surface = game.surface_spec(draw_four_pending, "Alice")
assert(draw_four_surface.zones.first.cards.map(&:id) == %w[Y R B G],
  "The Wild Draw Four colour selector is not ordered yellow, red, blue, green")
spoken = game.describe_event({ "id" => 10, "actor" => "Alice", "action" => "play", "value" => "NF0||0" },
  NewGames116Repository.new(state[:players]), draw_four_pending, "Alice")
assert(spoken == ["Alice played wild draw four.", "Choose a colour."],
  "The Wild Draw Four player was not prompted to choose a colour")
applied, history, = apply_uno_event(game, state, "choose_colour", "Y|1800000040", "Alice", 11)
assert(applied && state[:current_player] == "Bob" && state[:challenge_player] == "Bob",
  "Wild Draw Four did not assign the penalty or challenge after the colour choice")
assert(history.map(&:text) == ["Alice chose yellow."],
  "Wild Draw Four colour choice was not a separate announcement")

state = uno_wild_state(game, "NW0")
state[:hands]["Alice"] = ["NW0"]
apply_uno_event(game, state, "play", "NW0||0", "Alice", 20)
assert(state[:phase] == :playing && state[:pending_finisher] == "Alice",
  "Playing the last Wild ended the round before colour selection")
applied, history, = apply_uno_event(game, state, "choose_colour", "B|1800000050", "Alice", 21)
assert(applied && state[:phase] == :round_complete,
  "The round did not finish after selecting the colour of the last Wild")
assert(history.first.text == "Alice chose blue." && history.any? { |entry| entry.text == "Alice won the round." },
  "The final colour and round result are not ordered correctly")

puts "UNO staged Wild colour selection, interception lock and paused clock passed"
