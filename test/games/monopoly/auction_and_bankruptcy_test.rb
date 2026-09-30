require_relative "../../support/new_games_fixture"

game = GameRoomGames::Monopoly.new
players = %w[Alice Bob Carol]
repo = NewGames116Repository.new(players)
ctx = lambda { |now| GameRoomGames::ActionContext.new(now: now) }
view = lambda { |state| GameRoomGames::Replay.new(players: players, state: state, current_player: state[:current_player], winner: state[:winner], draw: false) }
fresh = lambda { game.send(:initial_state, players, game.normalize_options("auction_unsold" => true, "auction_decision_time" => 30)) }
state = fresh.call
state.update(phase: :property_decision)
state[:positions]["Alice"] = 3
history = []
game.send(:apply_decline, state, { "id" => 1, "value" => "1000" }, "Alice", repo, history)
assert(state[:auction_deadline] == 1030 && state[:current_player] == "Bob", "Auction timer did not start")
assert(history.last.text.start_with?("Auction begins:"), "Auction start is silent")
assert(!game.automatic_action_due?(view.call(state), "Alice", context: ctx.call(1029)), "Early timeout")
assert(!game.automatic_action_due?(view.call(state), "Bob", context: ctx.call(1030)), "Non-owner can resolve timeout")
status, late_plan = game.action_for({ "action" => "auction_timeout" }, view.call(state), "Alice", context: ctx.call(1030))
assert(status == :ok, "Timeout action unavailable")
timeout_event = { "id" => 3, "action" => "auction_timeout", "value" => late_plan.events.first.value }
%w[Bob Carol].each do |player|
  state[:current_player] = player
  shortcut = game.custom_game_shortcuts(view.call(state), player).find { |s| s.key == "b" }
  assert(shortcut.kind == :number_input && shortcut.allowed_values.begin == 1, "B does not accept arbitrary bid")
end
state[:current_player] = "Bob"
status, plan = game.action_for({ "action" => "auction_bid", "amount" => "37" }, view.call(state), "Bob", context: ctx.call(1029))
assert(status == :ok, "Custom amount refused")
game.send(:apply_auction, state, { "id" => 2, "action" => "auction_bid", "value" => plan.events.first.value }, "Bob", repo, history)
assert(state[:auction_bid] == 37 && state[:auction_deadline] == 1059 && state[:current_player] == "Carol", "Bid amount or timer reset is wrong")
assert(!game.send(:apply_auction_timeout, state, timeout_event, "Alice", repo, history), "Stale timeout passed a different bidder")
assert(!game.send(:apply_auction_timeout, state, timeout_event, "Bob", repo, history), "Non-owner timeout accepted")
status, plan = game.action_for({ "action" => "auction_timeout" }, view.call(state), "Alice", context: ctx.call(1059))
current_timeout = timeout_event.merge("value" => plan.events.first.value)
assert(game.send(:apply_auction_timeout, state, current_timeout, "Alice", repo, history), "Current timeout refused")
assert(state[:auction_passed]["Carol"] && state[:current_player] == "Alice", "Timeout did not pass only Carol")
assert(!game.send(:apply_auction_timeout, state, current_timeout, "Alice", repo, history), "Duplicate timeout applied twice")
game.send(:apply_auction, state, { "id" => 4, "action" => "auction_pass", "value" => "1060" }, "Alice", repo, history)
assert(state[:owners][3] == "Bob" && state[:cash]["Bob"] == state[:board_data][:starting_cash] - 37, "Auction settlement changed")
assert(state[:auction_deadline] == 0 && state[:phase] == :turn_complete, "Finished auction kept timer")
assert(game.options_error({ "auction_decision_time" => -1 }), "Negative timer accepted")
assert(game.default_options["auction_decision_time"] == 0, "Timer enabled by default")
state = fresh.call
state[:options]["auction_decision_time"] = 0
state[:phase] = :property_decision
state[:positions]["Alice"] = 3
game.send(:apply_decline, state, { "id" => 1, "value" => "1000" }, "Alice", repo, [])
assert(!game.automatic_action_due?(view.call(state), "Alice", context: ctx.call(9_999_999)), "Unlimited auction times out")
state[:cash]["Bob"] = 3
state[:auction_bid] = 1
assert(game.custom_game_shortcuts(view.call(state), "Bob").any? { |s| s.key == "b" }, "Small legal custom bid hidden when suggested increment is too large")
[-1, 1, 4].each do |amount|
  result = game.action_for({ "action" => "auction_bid", "amount" => amount }, view.call(state), "Bob", context: ctx.call(1001)).first
  assert(result == :invalid_auction_bid, "Invalid bid #{amount} accepted")
end

# Only liquidation options count as a rescue; never bankrupt someone while
# another player's move or a purchase/rent/trade decision is still running.
state = fresh.call
state[:cash]["Bob"] = -100
assert(!game.send(:unavoidable_bankruptcy?, state), "Other player's debt interrupts Alice")
state[:current_player] = "Bob"
state[:owners][1] = "Bob"
assert(!game.send(:unavoidable_bankruptcy?, state), "Bankrupted before mortgage")
state[:mortgaged][1] = true
assert(game.send(:unavoidable_bankruptcy?, state), "Mortgaged property delays bankruptcy")
%i[auction property_decision rent_decision trade_response].each do |phase|
  state[:phase] = phase
  assert(!game.send(:unavoidable_bankruptcy?, state), "Bankruptcy interrupts #{phase}")
end
state[:phase] = :awaiting_roll
state[:owners][3] = "Bob"
state[:mortgaged].clear
state[:houses].merge!(1 => 4, 3 => 4)
assert(!game.send(:unavoidable_bankruptcy?, state), "Bankrupted while buildings can be sold")
state[:houses].clear
state[:mortgaged].merge!(1 => true, 3 => true)
state[:debts]["Bob"] = [{ to: "Carol", amount: 100 }]
assert(game.automatic_action(view.call(state), "Alice", context: ctx.call(2000))["action"] == "bankrupt_auto", "Owner does not resolve unavoidable bankruptcy")
assert(game.automatic_action(view.call(state), "Bob", context: ctx.call(2000)) == nil, "Non-owner generates automatic bankruptcy")
status, plan = game.action_for({ "action" => "bankrupt_auto" }, view.call(state), "Alice", context: ctx.call(2000))
event = { "id" => 10, "action" => "bankrupt_auto", "value" => plan.events.first.value }
history = []
assert(game.send(:apply_automatic_bankruptcy, state, event, "Alice", repo, history), "Automatic bankruptcy rejected")
assert(state[:bankrupt]["Bob"] && state[:owners][1] == "Carol" && state[:owners][3] == "Carol", "Creditors lost assets")
assert(!game.send(:apply_automatic_bankruptcy, state, event, "Alice", repo, history), "Duplicate bankruptcy applied")
assert(history.any? { |h| h.text.include?("Bob") && h.text.include?("Carol") }, "Bankruptcy hides recipient")

# Full replay uses event timestamps, never wall-clock time. All readers agree.
session = { "options" => JSON.generate(game.normalize_options("auction_unsold" => true, "auction_decision_time" => 10)) }
events = [
  { "id" => 1, "actor" => "Alice", "action" => "roll", "value" => "1,2,#{'a' * 32}" },
  { "id" => 2, "actor" => "Alice", "action" => "decline", "value" => "1000" },
  { "id" => 3, "actor" => "Bob", "action" => "auction_bid", "value" => "37|1001" },
  { "id" => 4, "actor" => "Alice", "action" => "auction_timeout", "value" => "3|2|1011|1011" },
  { "id" => 5, "actor" => "Alice", "action" => "auction_pass", "value" => "1012" }
]
copies = Array.new(4) { game.replay(session, events, repo) }
assert(copies.all? { |copy| copy.accepted_events.length == 5 && copy.state == copies.first.state && copy.history.map(&:text) == copies.first.history.map(&:text) }, "Auction replay diverges")
assert(copies.first.state[:owners][3] == "Bob", "Replay did not award auction")
puts "Monopoly auction input, deadlines, stale/duplicate events, zero limit, bankruptcy and four-reader replay passed"
