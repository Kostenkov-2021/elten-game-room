require_relative "../../support/new_games_fixture"

game = GameRoomGames::Monopoly.new
players = %w[Alice Bob Carol]
repo = NewGames116Repository.new(players)
context = GameRoomGames::ActionContext.new(now: 1000)
view = lambda do |state|
  GameRoomGames::Replay.new(players: players, state: state,
    current_player: state[:current_player], winner: state[:winner], draw: false)
end
fresh = lambda do |auction|
  game.send(:initial_state, players, game.normalize_options(
    "auction_unsold" => auction, "auction_decision_time" => 30))
end

# The person choosing a purchase need not own the table. Use an ordinary
# decline event, with the same actor, validation and auction path as Enter.
[1, 5, 12].each do |index|
  [false, true].each do |auction|
    state = fresh.call(auction)
    state.update(phase: :property_decision, current_player: "Bob")
    state[:positions]["Bob"] = index
    price = state[:board][index][:price]
    state[:cash]["Bob"] = price - 1
    replay = view.call(state)
    assert(game.automatic_action_allowed?(replay, "Bob", table_owner: "Alice"), "Non-owner purchase cannot be resolved automatically")
    assert(game.automatic_action_due?(replay, "Bob", context: context), "Unaffordable purchase still requires Enter")
    assert(!game.automatic_action_due?(replay, "Alice", context: context), "Owner impersonates the buyer")
    selection = game.automatic_action(replay, "Bob", context: context)
    assert(selection == { "kind" => "command", "action" => "decline" }, "Automatic refusal changes the event format")
    status, plan = game.action_for(selection, replay, "Bob", context: context)
    assert(status == :ok && plan.events.first.value == "1000", "Automatic refusal is not a normal valid action")
    event = { "id" => 3, "action" => plan.events.first.action, "value" => plan.events.first.value }
    history = []
    assert(!game.send(:apply_decline, state, event, "Alice", repo, history), "Wrong buyer may decline")
    assert(game.send(:apply_decline, state, event, "Bob", repo, history), "Automatic decline was rejected")
    assert(state[:cash]["Bob"] == price - 1 && state[:owners][index] == nil, "Decline spends money or transfers property")
    if auction
      assert(state[:phase] == :auction && state[:current_player] == "Carol", "Automatic refusal bypasses the auction")
      assert(state[:auction_deadline] == 1030 && state[:auction_square] == index, "Automatic auction loses its timer or property")
    else
      game.send(:advance_completed_turn, state)
      assert(state[:phase] == :awaiting_roll && state[:current_player] == "Carol", "Decline leaves a required End turn")
    end
    assert(!game.send(:apply_decline, state, event, "Bob", repo, history), "Duplicate refusal applied")
  end
end

state = fresh.call(false)
state.update(phase: :property_decision, current_player: "Bob")
state[:positions]["Bob"] = 1
state[:cash]["Bob"] = state[:board][1][:price]
assert(!game.automatic_action_due?(view.call(state), "Bob", context: context), "Exactly enough cash is refused")
assert(game.automatic_action(view.call(state), "Bob", context: context) == nil, "Affordable purchase is automatic")
state[:cash]["Bob"] = 0
%i[awaiting_roll rent_decision trade_response turn_complete auction].each do |phase|
  state[:phase] = phase
  assert(!game.automatic_action_due?(view.call(state), "Bob", context: context), "Low cash auto-declines #{phase}")
end

# A complete replay exercises a non-owner's landing and normal decline event.
# Only the test's initial cash is smaller; the event/replay engine is real.
class LowCashMonopoly < GameRoomGames::Monopoly
  private

  def initial_state(players, options)
    super.tap { |state| state[:cash]["Bob"] = state[:board][5][:price] - 1 }
  end
end

game = LowCashMonopoly.new
[false, true].each do |auction|
  session = { "options" => JSON.generate(game.normalize_options(
    "auction_unsold" => auction, "auction_decision_time" => 30)) }
  events = [
    { "id" => 1, "actor" => "Alice", "action" => "roll", "value" => "1,2,#{'a' * 32}" },
    { "id" => 2, "actor" => "Alice", "action" => "buy", "value" => "" },
    { "id" => 3, "actor" => "Bob", "action" => "roll", "value" => "1,4,#{'b' * 32}" }
  ]
  replay = game.replay(session, events, repo)
  assert(replay.state[:phase] == :property_decision && replay.current_player == "Bob", "Fixture did not reach the purchase")
  replay = append_action(game, session, repo, events, replay, "Bob",
    game.automatic_action(replay, "Bob", context: context), context)
  copies = Array.new(3) { game.replay(session, events, repo) }
  assert(copies.all? { |copy| copy.state == replay.state && copy.accepted_events.length == 4 && copy.history.map(&:text) == replay.history.map(&:text) }, "Refusal replay diverges")
  assert(replay.current_player == "Carol" && replay.state[:phase] == (auction ? :auction : :awaiting_roll), "Replay did not advance")
end

puts "Monopoly unaffordable purchases: human non-owner, streets/stations/utilities, optional auctions, exact cash, duplicate events and four-reader replay passed"
