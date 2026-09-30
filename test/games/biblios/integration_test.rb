# encoding: UTF-8
require_relative "../../support/biblios"
require_relative "../../../lib/game_sounds"

game = GameRoomGames::Biblios.new
players = %w[Alice Bob Carol]
repository = NewGames116Repository.new(players)
session = { "options" => JSON.generate(game.default_options) }
events = []
replay = game.replay(session, events, repository)
assert(game.action_for({ "action" => "start" }, replay, "Bob", context: context_for).first == :not_your_turn, "non-controller started")
forged = { "id" => 1, "actor" => "Bob", "action" => "start", "value" => "a" * 32 }
assert(game.replay(session, [forged], repository).accepted_events.empty?, "forged start replayed")
assert(game.replay(session, [forged.merge("actor" => "Alice", "value" => "bad")], repository).accepted_events.empty?, "bad seed replayed")
before = replay
replay = append_action(game, session, repository, events, replay, "Alice", { "action" => "start" }, context_for)
assert(GameRoomSounds.event_cue(game: game, event: events.last, before_replay: before, after_replay: replay, repository: repository, viewer: "Alice") == "shuffle", "no deal sound")
replay = append_action(game, session, repository, events, replay, "Alice", { "action" => "allocate", "place" => "public" })
duplicate = game.replay(session, events + [events.last.dup], repository)
assert(duplicate.state == replay.state && duplicate.accepted_events.length == events.length, "repeated delivery allocated twice")

# A 62-card payment is still one event under the server's 64-character limit.
state = blank_state(game, players)
auctioned = "o18"
hand = game.send(:master_deck).reject { |card| game.church?(card) || card == auctioned }
state.merge!(phase: :pay, current_player: "Alice", card: auctioned, high: hand.length, bidder: "Alice", seed: "b" * 32)
state[:hands]["Alice"] = hand.dup
state[:revealed]["Alice"] = hand.first(6)
payment_replay = replay_of(state)
status, plan = game.action_for({ "action" => "pay", "cards" => JSON.generate(hand) }, payment_replay, "Alice")
assert(status == :ok && plan.events.one? && plan.events.first.value.length <= 64, "payment does not fit a single record")
assert(game.send(:parse_cards, plan.events.first.value) == hand, "payment mask lost cards")
assert(game.send(:parse_cards, '~' + (1 << 87).to_s(16)) == nil, "out-of-deck mask accepted")
assert(game.send(:parse_cards, '~xyz') == nil, "invalid mask accepted")
['[', '[1]', '["decline","pA"]', '["pA","pA"]'].each do |value|
  snapshot = Marshal.dump(state)
  assert(game.action_for({ "action" => "pay", "cards" => value }, payment_replay, "Alice").first == :invalid_payment, "malformed payment penalised or accepted")
  assert(!game.send(:apply_pay, state, { "id" => 20, "value" => value }, "Alice", repository, []), "malformed payment replayed")
  assert(snapshot == Marshal.dump(state), "invalid payment mutated game")
end
assert(game.send(:apply_pay, state, { "id" => 20, "value" => plan.events.first.value }, "Alice", repository, []), "compact payment cannot replay")
assert(state[:hands]["Alice"] == [auctioned] && state[:revealed]["Alice"] == [auctioned], "face-down payment leaked exact discarded identities")

# Navigation must expose every usable physical card, including equal-value
# alternatives, while leaving the choice of packet entirely to the player.
state = blank_state(game, players)
state.merge!(phase: :pay, current_player: "Alice", card: "mH", high: 2)
state[:hands]["Alice"] = %w[o1 o2 o7 o8 o13 mA]
spec = game.playable_card_navigation(replay_of(state), "Alice")
assert(spec[:card_actions].keys.sort == %w[o1 o2 o7 o8 o13].sort, "payment navigation omitted legal alternatives")
assert(spec[:automatic_card_ids].empty?, "payment was marked automatic")
spec[:card_actions].each_value do |choices|
  choices.each { |choice| assert(game.action_for(choice, replay_of(state), "Alice").first == :ok, "navigation includes impossible packet") }
end
assert(game.playable_card_navigation(replay_of(state), "Observer") == nil, "observer sees payment hand")
state[:high] = 100
assert(game.playable_card_navigation(replay_of(state), "Alice")[:card_actions].empty?, "cannot afford payment but Z is legal")

# With an insufficient hand, the full penalty starts at the next player.
state = blank_state(game, players, "penalty" => "full")
state.merge!(phase: :pay, current_player: "Bob", card: "mI", seed: "c" * 32)
state[:hands]["Bob"] = %w[pA]
state[:revealed]["Bob"] = %w[pA]
game.send(:penalise, state, "Bob", 4, [])
assert(state[:hands]["Carol"] == %w[pA] && state[:hands]["Alice"].empty?, "full penalty ignored circular order")
assert(state[:revealed].values.flatten.empty?, "secret penalty card disclosed")

# Every planning phase must be invariant to opponents' unrevealed cards
# and unseen future draws. Public knowledge may still inform decisions.
state = blank_state(game, players)
state.merge!(phase: :allocate, current_player: "Alice", deck: %w[mH pI fA], pointer: 0)
state[:hands]["Alice"] = %w[mA mB o1 o7 o13]
state[:hands]["Bob"] = %w[mC pB]
state[:revealed]["Bob"] = %w[mC]
[:allocate, :take, :church, :auction, :pay].each do |phase|
  state[:phase] = phase
  state[:public] = %w[mI pH fI]
  state[:church] = { "player" => "Alice", "card" => church_card(game, "any1"), "resume" => "allocate" }
  state[:card] = "mI"
  state[:high] = phase == :pay ? 2 : 0
  altered = Marshal.load(Marshal.dump(state))
  altered[:hands]["Bob"] = %w[mC mD mE mF mG pC pD]
  altered[:hands]["Carol"] = %w[fA fB fC fD]
  altered[:deck] = %w[mH sI hI]
  one, two = replay_of(state), replay_of(altered)
  assert(game.bot_observation(one, "Alice") == game.bot_observation(two, "Alice"), "observation leaks hidden #{phase} state")
  actions = game.legal_actions(one, "Alice")
  scores = actions.map { |action| game.bot_action_score(one, "Alice", action) }
  hidden_scores = actions.map { |action| game.bot_action_score(two, "Alice", action) }
  assert(scores == hidden_scores, "bot used hidden information in #{phase}")
  first = game.bot_strategy.choose(actions: actions, actor: "Alice", random_source: NewGames116Random.new, game: game, replay: one)
  second = game.bot_strategy.choose(actions: actions, actor: "Alice", random_source: NewGames116Random.new, game: game, replay: two)
  assert(first == second, "hidden cards changed #{phase} decision")
end
state[:phase] = :auction
assert(game.action_for({ "action" => "bid", "amount" => "3x" }, replay_of(state), "Alice").first == :invalid_bid, "non-numeric bid accepted")
puts "Biblios integration, payment bounds, replay, navigation, sounds and bot privacy passed."
