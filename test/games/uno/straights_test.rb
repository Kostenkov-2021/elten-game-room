require_relative "../../support/ui"
require_relative "../../support/log"

class Program
  def self.server_app(**_options); end
end

require_relative "../../../__app"

def assert(value, message)
  raise message unless value
end

class UnoStraightRepository
  attr_reader :players

  def initialize(players)
    @players = players
  end

  def players_for(_session); players; end
  def actor_of(event, _session = nil); event["actor"]; end
  def event_id(event); event["id"]; end
end

def uno_state(game, options = {})
  players = %w[Alice Bob Carol]
  game.send(:initial_state, players, game.normalize_options({
    "straights" => true,
    "interceptions" => false,
    "thinking_time" => 30
  }.merge(options))).merge(
    phase: :playing,
    round: 1,
    current_player: "Alice",
    discard: ["R00"],
    colour: "R",
    turn_deadline: 130,
    hands: {
      "Alice" => %w[R51 R42 R33 R64 G41],
      "Bob" => %w[R91 B22],
      "Carol" => %w[R52 Y31]
    }
  )
end

def uno_replay(state, history = [])
  GameRoomGames::Replay.new(
    players: state[:players],
    current_player: state[:current_player],
    winner: state[:winner],
    draw: false,
    accepted_events: [],
    history: history,
    state: state
  )
end

def uno_play(game, state, card, actor, id, deadline = 130)
  event = { "id" => id, "actor" => actor, "action" => "play", "value" => "#{card}||#{deadline}" }
  history = []
  applied = game.send(:apply_play, state, event, actor, UnoStraightRepository.new(state[:players]), history)
  [applied, history, event]
end

game = GameRoomGames::Uno.new
assert(game.default_options["straights"] == false, "Straights are not optional and off by default")

state = uno_state(game)
assert(uno_play(game, state, "R51", "Alice", 1).first, "The first card could not start a straight")
assert(state[:current_player] == "Bob" && state[:straight_actor] == "Alice", "The first card did not expose the race to Bob")
alice_actions = game.legal_actions(uno_replay(state), "Alice")
assert(alice_actions.any? { |action| action["card"] == "R42" && action["straight"] }, "Descending continuation is unavailable")
assert(alice_actions.any? { |action| action["card"] == "R64" && action["straight"] }, "Ascending continuation is unavailable")
status, plan = game.action_for({ "kind" => "card", "action" => "select", "card_id" => "R42", "card" => "R42" },
  uno_replay(state), "Alice", context: GameRoomGames::ActionContext.new(now: 500))
assert(status == :ok && plan.events.first.value.end_with?("|130"), "The UI path rejected a straight or reset the next player's clock")
assert(uno_play(game, state, "R42", "Alice", 2).first, "The first descending continuation failed")
assert(state[:current_player] == "Bob" && state[:straight_direction] == -1 && state[:turn_deadline] == 130,
  "A straight continuation stole Bob's turn or reset the clock")
assert(uno_play(game, state, "R33", "Alice", 3).first, "The descending straight could not continue")
assert(!uno_play(game, state, "R64", "Alice", 4).first, "The straight changed direction after it was established")

bot_state = uno_state(game)
bot_state[:players][0] = "bot:1:1"
bot_state[:hands]["bot:1:1"] = bot_state[:hands].delete("Alice")
bot_state[:scores]["bot:1:1"] = bot_state[:scores].delete("Alice")
bot_state[:eliminated]["bot:1:1"] = bot_state[:eliminated].delete("Alice")
bot_state[:round_eliminated]["bot:1:1"] = bot_state[:round_eliminated].delete("Alice")
bot_state[:current_player] = "bot:1:1"
uno_play(game, bot_state, "R51", "bot:1:1", 5)
assert(game.active_actors(uno_replay(bot_state)).first == "bot:1:1", "A following bot took the turn before the straight bot could continue")

state = uno_state(game)
uno_play(game, state, "R51", "Alice", 10)
assert(uno_play(game, state, "R91", "Bob", 11).first, "Bob could not answer the first straight card")
assert(state[:straight_actor] == "Bob", "Bob's move did not close and replace Alice's straight")
assert(!uno_play(game, state, "R42", "Alice", 12).first, "Alice continued after Bob had played")

state = uno_state(game, "interceptions" => true)
uno_play(game, state, "R51", "Alice", 20)
applied, interception_history, = uno_play(game, state, "R52", "Carol", 21)
assert(applied && state[:current_player] == "Carol", "An interception did not take over the turn")
assert(interception_history.any? { |entry| entry.key.start_with?("interception:") }, "The interception was not marked for its sound")
discard_after_interception = state[:discard].dup
assert(uno_play(game, state, "R42", "Alice", 22).first, "The late attempt was not recorded")
assert(state[:discard] == discard_after_interception && state[:hands]["Alice"].include?("R42") && state[:scores]["Alice"] == 3,
  "A straight survived another player's interception")

state = uno_state(game, "interceptions" => true)
state[:current_player] = "Bob"
state[:discard] = ["RD0"]
state[:colour] = "R"
state[:hands]["Alice"] = %w[RD1 G30]
before = Marshal.load(Marshal.dump(state))
applied, history, event = uno_play(game, state, "RD1", "Alice", 30)
assert(applied && state[:pending_draw] == 2, "Draw Two interception did not create its penalty")
assert(state[:current_player] == "Bob", "The Draw Two penalty was assigned to the interceptor instead of the interrupted player")
cue = GameRoomSounds.event_cue(
  game: game,
  event: event,
  before_replay: uno_replay(before),
  after_replay: uno_replay(state, history),
  repository: UnoStraightRepository.new(state[:players]),
  viewer: "Alice"
)
assert(cue == ["play", "interception"], "A successful interception did not keep both card and interception sounds")

plain = uno_replay(uno_state(game), [])
assert(GameRoomSounds.event_cue(game: game, event: { "id" => 40, "action" => "play", "value" => "RS1||0" },
  before_replay: plain, after_replay: plain, repository: UnoStraightRepository.new(plain.players), viewer: "Alice") == ["play", "skip"],
  "Skip does not keep both card and skip sounds")
assert(GameRoomSounds.event_cue(game: game, event: { "id" => 41, "action" => "play", "value" => "RV1||0" },
  before_replay: plain, after_replay: plain, repository: UnoStraightRepository.new(plain.players), viewer: "Alice") == ["play", "reverse3"],
  "Reverse does not keep both card and reverse sounds")

timer_state = uno_state(game)
timer_state[:turn_deadline] = Time.now.to_i + 30
timer_replay = uno_replay(timer_state)
assert(!game.turn_announcement(timer_replay, "Alice").include?("seconds"), "Automatic turn speech still announces the clock")
assert(game.send(:current_turn_shortcut_text, timer_replay, "Alice").include?("seconds"), "T no longer reports the remaining time")

puts "UNO straight, interception penalty, timer speech and sound regressions passed"
