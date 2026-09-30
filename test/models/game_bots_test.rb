require_relative "../../lib/game_surfaces/specifications"
require_relative "../support/sequence_random"

def _(text)
  text
end


require_relative "../../lib/game_participants"
require_relative "../../lib/game_random"
require_relative "../../lib/game_bots"
require_relative "../../games/base"
require_relative "../../games/four_in_a_row"
require_relative "../../games/tic_tac_toe"

def assert(condition, message)
  raise message if !condition
end

class BotGameRepository
  attr_accessor :players

  def initialize(players)
    @players = players
  end

  def players_for(_session)
    @players
  end

  def actor_of(event, _session = nil)
    event.fetch("actor")
  end

  def event_id(event)
    event.fetch("id")
  end
end

bot = GameRoomParticipants.bot_id(7, 1)
assert(GameRoomParticipants.bot?(bot), "a computer id was not recognized")
assert(GameRoomParticipants.display_name(bot) == "Computer 1", "a computer has an invalid display name")
assert(
  GameRoomParticipants.humans(["Alice", bot, "alice", "Bob"]) == ["Alice", "Bob"],
  "computer or duplicate users leaked into signal recipients"
)

game = GameRoomGames::TicTacToe.new
repository = BotGameRepository.new(["Alice", bot])
session = {}
after_human_move = game.replay(
  session,
  [{ "id" => 1, "actor" => "Alice", "action" => "place", "value" => "1,1" }],
  repository
)
assert(after_human_move.current_player == bot, "the computer did not receive its turn")

context = GameRoomGames::ActionContext.new(
  session_id: 11,
  table_id: 7,
  random_source: GameRoomRandom::SequenceSource.new([2]),
  now: 100
)
coordinator = GameRoomBots::Coordinator.new
assert(coordinator.pending_bot(game, after_human_move) == bot, "the coordinator did not detect a computer turn")
decision = coordinator.decide(game: game, replay: after_human_move, actor: bot, context: context)
assert(decision != nil && decision.actor == bot, "the coordinator did not create a computer decision")
assert(decision.available_actions.length == 8, "the computer received an invalid legal action list")
assert(decision.action["x"] == 1 && decision.action["y"] == 1, "the heuristic strategy did not choose the center")

status, plan = game.action_for(decision.action, after_human_move, bot, context: context)
assert(status == :ok && plan.events.length == 1, "the computer decision did not pass normal game validation")
bot_event = {
  "id" => 2,
  "actor" => bot,
  "action" => plan.events.first.action,
  "value" => plan.events.first.value
}
after_bot_move = game.replay(
  session,
  [
    { "id" => 1, "actor" => "Alice", "action" => "place", "value" => "1,1" },
    bot_event
  ],
  repository
)
assert(after_bot_move.accepted_events.length == 2, "the game rejected a validated computer move")
assert(after_bot_move.current_player == "Alice", "the turn did not return to the human player")
assert(after_bot_move.history.last.text.include?("Computer 1"), "history exposed a technical computer id")

four_in_a_row = GameRoomGames::FourInARow.new
four_repository = BotGameRepository.new(["Alice", bot])
finished_by_bot = four_in_a_row.replay(
  session,
  [
    ["Alice", "7"],
    [bot, "1"],
    ["Alice", "7"],
    [bot, "2"],
    ["Alice", "6"],
    [bot, "3"],
    ["Alice", "6"],
    [bot, "4"]
  ].each_with_index.map do |(actor, column), index|
    { "id" => index + 1, "actor" => actor, "action" => "drop", "value" => column }
  end,
  four_repository
)
assert(finished_by_bot.finished?, "the Connect Four fixture did not finish")
assert(finished_by_bot.current_player == bot, "the fixture no longer reproduces the stale bot turn")
assert(
  coordinator.pending_bot(four_in_a_row, finished_by_bot) == nil,
  "a finished game still exposes a pending computer"
)
assert(
  coordinator.decide_next(
    game: four_in_a_row,
    replay: finished_by_bot,
    context: context
  ) == nil,
  "the coordinator still plans after the game has finished"
)
assert(
  coordinator.decide(
    game: four_in_a_row,
    replay: finished_by_bot,
    actor: bot,
    context: context
  ) == nil,
  "a direct computer decision bypasses the finished-game guard"
)

puts "Game bot framework tests passed"
