require_relative "../../lib/game_surfaces/specifications"
def _(text)
  text
end

def assert(condition, message)
  raise message if !condition
end

require_relative "../../lib/bot_turn_gate"
require_relative "../../lib/game_participants"


require_relative "../../games/base"
require_relative "../../lib/game_bots"
require_relative "../../lib/farkle_strategy"
require_relative "../../games/farkle"

Row = Struct.new(:id, :actor, :action, :value, keyword_init: true)
PlanEvent = Struct.new(:action, :value, keyword_init: true)

def row(id, actor, action, value = "")
  { "id" => id, "actor" => actor, "action" => action, "value" => value }
end

def submit(controller, lease, events, ids: nil, failed: false)
  assert(controller.submitting(lease, events: events), "controller rejected a leased bot plan")
  if failed
    assert(controller.submission_failed(lease), "controller did not retain an uncertain bot action")
  else
    assert(controller.submitted(lease, event_ids: ids), "controller did not wait for submitted event IDs")
  end
end

clock = 0.0
paced_clock = 0.0
paced = GameRoomBots::TurnController.new(clock: -> { paced_clock })
paced.schedule_decision(session_id: 90, actor: "bot:7:1", revision: [1, 1], delay: 3)
assert(!paced.ready?(session_id: 90, actor: "bot:7:1"), "Pacing did not delay the first decision")
assert(!paced.acquire(session_id: 90, actor: "bot:7:1", revision: [1, 1]), "Acquire bypassed pacing")
paced_clock = 2
paced.schedule_decision(session_id: 90, actor: "bot:7:1", revision: [1, 1], delay: 3)
paced_clock = 3
assert(paced.ready?(session_id: 90, actor: "bot:7:1"), "An unchanged refresh restarted the countdown")
paced_lease = paced.acquire(session_id: 90, actor: "bot:7:1", revision: [1, 1])
paced.cancel(paced_lease)
assert(paced.ready?(session_id: 90, actor: "bot:7:1"), "Cancellation postponed an already ready bot")
paced.schedule_decision(session_id: 90, actor: "bot:7:2", revision: [2, 2], delay: 5)
assert(!paced.ready?(session_id: 90, actor: "bot:7:2"), "Next bot ignored its delay")
paced.switch_session(91)
assert(paced.ready?(session_id: 91, actor: "bot:7:2"), "Old session's delay leaked into the next game")
controller = GameRoomBots::TurnController.new(clock: -> { clock })
bot_one = "bot:7:1"
bot_two = "bot:7:2"
play = [PlanEvent.new(action: "play", value: "03H|normal")]
lease = controller.acquire(session_id: 12, actor: bot_one, revision: [1, 10])
assert(lease != nil, "the first computer could not start")
submit(controller, lease, play, ids: [11])
assert(!controller.ready?(session_id: 12, actor: bot_two), "the next computer started before confirmation")
assert(
  controller.observe(
    session_id: 12,
    events: [row(10, "Alice", "start"), row(11, bot_one, "play", "03H|normal")],
    confirmed_event_ids: [10],
    verified: false
  ) == :waiting_for_confirmation,
  "an optimistic event was mistaken for server confirmation"
)
clock = 2.0
assert(controller.verification_due?, "the delayed control read did not become due")
controller.defer_verification
assert(!controller.verification_due?, "a failed control read would retry in a tight loop")
clock = 4.0
assert(
  controller.observe(
    session_id: 12,
    events: [row(10, "Alice", "start"), row(11, bot_one, "play", "03H|normal")],
    confirmed_event_ids: [10, 11],
    verified: true
  ) == :confirmed,
  "a server-confirmed move did not release the controller"
)
assert(controller.ready?(session_id: 12, actor: bot_two), "the next computer did not start after server confirmation")

# A failed response may still mean that the server saved the whole action.
lease = controller.acquire(session_id: 12, actor: bot_two, revision: [2, 11])
submit(controller, lease, play, failed: true)
clock = 7.0
assert(
  controller.observe(
    session_id: 12,
    events: [row(12, bot_two, "play", "03H|normal")],
    confirmed_event_ids: [12],
    verified: true
  ) == :confirmed,
  "an uncertain but saved move would be duplicated"
)

# If the control read proves that nothing was saved, a new decision is allowed
# immediately. The old decision object is never retained by the controller.
clock = 8.0
lease = controller.acquire(session_id: 12, actor: bot_one, revision: [3, 12])
submit(controller, lease, play, failed: true)
clock = 10.0
assert(
  controller.observe(
    session_id: 12,
    events: [row(12, bot_two, "play", "03H|normal")],
    confirmed_event_ids: [12],
    verified: true
  ) == :not_saved,
  "a confirmed missing action did not request a fresh decision"
)
assert(controller.ready?(session_id: 12, actor: bot_one), "a missing write received an unnecessary cooldown")

# A multi-event game action may still be only partly persisted by a failed
# request. Seeing its saved prefix must discard the old complete decision.
pair = [
  PlanEvent.new(action: "play", value: "03H|normal"),
  PlanEvent.new(action: "draw", value: "")
]
lease = controller.acquire(session_id: 12, actor: bot_one, revision: [3, 12])
submit(controller, lease, pair, failed: true)
clock = 12.0
assert(
  controller.observe(
    session_id: 12,
    events: [row(13, bot_one, "play", "03H|normal")],
    confirmed_event_ids: [13],
    verified: true
  ) == :partially_confirmed,
  "a saved play from a failed play/draw pair was not reconciled"
)
clock = 13.0
lease = controller.acquire(session_id: 12, actor: bot_one, revision: [4, 13])
draw = [PlanEvent.new(action: "draw", value: "")]
submit(controller, lease, draw, ids: [14])
assert(
  controller.observe(
    session_id: 12,
    events: [row(14, bot_one, "draw")],
    confirmed_event_ids: [14]
  ) == :confirmed,
  "the missing draw was not completed as a separate confirmed action"
)

# Three consecutive computer seats are serialized by server confirmation, not
# by a fixed delay or by the time their planners take.
clock = 20.0
controller = GameRoomBots::TurnController.new(clock: -> { clock })
%w[bot:9:1 bot:9:2 bot:9:3].each_with_index do |actor, index|
  event_id = 101 + index
  lease = controller.acquire(session_id: 21, actor: actor, revision: [index, event_id - 1])
  assert(lease != nil, "computer #{index + 1} did not receive its serialized turn")
  submit(controller, lease, play, ids: [event_id])
  controller.observe(
    session_id: 21,
    events: [row(event_id, actor, "play", "03H|normal")],
    confirmed_event_ids: [event_id]
  )
  clock += 1.0
end

# Farkle must not expose Roll, Keep or Bank while another participant owns the
# turn. The surrounding history, users and shortcut fields are built by
# GameScreen and remain independent from this surface.
farkle = GameRoomGames::Farkle.new
state = {
  phase: :awaiting_roll,
  current_player: "bot:5:1",
  dice_to_roll: 6,
  turn_points: 0,
  scores: {},
  players: ["Alice", "bot:5:1"]
}
replay = GameRoomGames::Replay.new(players: state[:players], current_player: state[:current_player], state: state)
surface = farkle.surface_spec(replay, "Alice")
assert(surface.zones.first.cards.empty?, "Farkle exposed human action fields during the computer turn")

state[:current_player] = "Bob"
state[:players] = ["Alice", "Bob"]
replay = GameRoomGames::Replay.new(players: state[:players], current_player: state[:current_player], state: state)
surface = farkle.surface_spec(replay, "Alice")
assert(surface.zones.first.cards.empty?, "Farkle exposed action fields during another human player's turn")
assert(surface.zones.first.header.include?("Bob"), "Farkle did not identify the human player whose turn is active")

state[:current_player] = "Alice"
replay = GameRoomGames::Replay.new(players: state[:players], current_player: state[:current_player], state: state)
surface = farkle.surface_spec(replay, "Alice")
assert(surface.zones.first.cards.map(&:id).include?("roll"), "Farkle hid Roll from the human player whose turn is active")

clock = 30.0
controller = GameRoomBots::TurnController.new(clock: -> { clock })
lease = controller.acquire(session_id: 30, actor: bot_one, revision: [0, 0])
submit(controller, lease, play, ids: [1])
controller.switch_session(31)
assert(
  controller.ready?(session_id: 31, actor: bot_two),
  "an old game's pending computer action blocked a new game"
)

puts "Bot turn controller tests passed: confirmation, recovery, partial actions and sequential computers"
