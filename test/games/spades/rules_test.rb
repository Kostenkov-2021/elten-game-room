require_relative "../../../lib/game_surfaces/specifications"
require_relative "../../support/sequence_random"

def _(text)
  text
end


require "json"
require_relative "../../../lib/game_random"
require_relative "../../../games/base"
require_relative "../../../games/spades"

class SpadesRepository
  attr_reader :players

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

def assert(condition, message)
  raise message if !condition
end

def spades_event(id, actor, action, value)
  { "id" => id, "actor" => actor, "action" => action, "value" => value.to_s }
end

def spades_session(options = {})
  { "options" => JSON.generate(options) }
end

players = ["Alice", "Bob", "Carol", "Dave"]
game = GameRoomGames::Spades.new
repository = SpadesRepository.new(players)

assert(game.minimum_players == 3, "Spades does not allow three players")
assert(game.maximum_players == 6, "Spades does not allow six players")
assert(game.supports_bots?, "Spades does not expose bot support")
assert(game.send(:card_label, "TC") == "10 of clubs", "Spades still reads numeric ranks as words")
playroom_hand = %w[AS 2H AC TC 2S AH AD 2C 2D].sort_by do |card|
  game.send(:card_sort_key, card)
end
assert(
  playroom_hand == %w[2H AH 2S AS 2D AD 2C TC AC],
  "Spades does not use the Playroom suit order with low-to-high ranks"
)
assert(game.default_options["score_limit"] == 300, "the default score limit is not 300")
assert(game.default_options["team_size"] == 0, "individual play is not the default")
assert(
  game.option_definitions.find { |definition| definition.key == "score_limit" }.kind == :integer,
  "the score limit is not an editable number"
)
assert(
  game.options_error({ "team_size" => 2 }, player_count: 3) != nil,
  "teams of two were allowed with three players"
)
assert(
  game.options_error({ "team_size" => 0, "suicide" => true }, player_count: 4) != nil,
  "Suicide was allowed in individual play"
)
assert(game.options_error({ "team_size" => 2 }, player_count: 6) == nil, "three pairs were rejected")
assert(game.options_error({ "team_size" => 3 }, player_count: 6) == nil, "two teams of three were rejected")
assert(
  game.options_error({ "team_size" => 3 }, player_count: 4) != nil,
  "teams of three were allowed with four players"
)
assert(
  game.normalize_options("partnership" => false)["team_size"] == 0,
  "an existing individual table became a team table"
)
assert(
  game.normalize_options("partnership" => true)["team_size"] == 2,
  "an existing partnership table lost its teams"
)

normal = {
  "partnership" => false,
  "quicksand" => false
}
scoring = GameRoomGames::Spades::Scoring.new(players, normal)
exact = scoring.apply(
  bids: { "Alice" => 2, "Bob" => 3, "Carol" => 3, "Dave" => 3 },
  tricks: { "Alice" => 2, "Bob" => 3, "Carol" => 3, "Dave" => 5 },
  scores: {}
)
assert(exact.scores["Alice"] == 40, "the exact one-or-two bid bonus is incorrect")

difficult = scoring.apply(
  bids: { "Alice" => 10, "Bob" => 1, "Carol" => 1, "Dave" => 1 },
  tricks: { "Alice" => 11, "Bob" => 1, "Carol" => 1, "Dave" => 0 },
  scores: {}
)
assert(difficult.scores["Alice"] == 141, "the difficult-contract bonus is incorrect")

quicksand = GameRoomGames::Spades::Scoring.new(
  players,
  normal.merge("quicksand" => true)
)
quicksand_result = quicksand.apply(
  bids: { "Alice" => 3, "Bob" => 3, "Carol" => 3, "Dave" => 3 },
  tricks: { "Alice" => 5, "Bob" => 1, "Carol" => 3, "Dave" => 4 },
  scores: {}
)
assert(quicksand_result.scores["Alice"] == 10, "Quicksand overtricks are scored incorrectly")
assert(quicksand_result.scores["Bob"] == -20, "a failed Quicksand contract is scored incorrectly")

quicksand_example = quicksand.apply(
  bids: { "Alice" => 7, "Bob" => 2, "Carol" => 2, "Dave" => 2 },
  tricks: { "Alice" => 9, "Bob" => 2, "Carol" => 1, "Dave" => 1 },
  scores: {}
)
assert(
  quicksand_example.scores["Alice"] == 50,
  "the documented seven-bid Quicksand example did not score 50"
)

partnership = GameRoomGames::Spades::Scoring.new(
  players,
  normal.merge("partnership" => true)
)
nil_result = partnership.apply(
  bids: { "Alice" => 0, "Bob" => 3, "Carol" => 4, "Dave" => 3 },
  tricks: { "Alice" => 1, "Bob" => 3, "Carol" => 5, "Dave" => 4 },
  scores: {}
)
assert(nil_result.scores["team:0"] == -58, "failed nil or partnership bags are incorrect")

bag_score = scoring.apply(
  bids: { "Alice" => 3, "Bob" => 3, "Carol" => 3, "Dave" => 3 },
  tricks: { "Alice" => 8, "Bob" => 1, "Carol" => 2, "Dave" => 2 },
  scores: { "Alice" => 70 }
)
assert(bag_score.scores["Alice"] == 105, "five bags were not included in the total score")
bag_penalty = scoring.apply(
  bids: { "Alice" => 3, "Bob" => 3, "Carol" => 3, "Dave" => 3 },
  tricks: { "Alice" => 8, "Bob" => 1, "Carol" => 2, "Dave" => 2 },
  scores: bag_score.scores
)
assert(bag_penalty.scores["Alice"] == 40, "the tenth bag did not apply a 100-point penalty")

six_players = ["Alice", "Bob", "Carol", "Dave", "Eve", "Frank"]
pairs = GameRoomGames::Spades::Scoring.new(six_players, "team_size" => 2)
assert(pairs.unit_ids == ["team:0", "team:1", "team:2"], "six-player pairs did not create three teams")
assert(pairs.members_for("team:0") == ["Alice", "Dave"], "the first six-player pair has wrong seats")
assert(pairs.members_for("team:1") == ["Bob", "Eve"], "the second six-player pair has wrong seats")
assert(pairs.members_for("team:2") == ["Carol", "Frank"], "the third six-player pair has wrong seats")

triples = GameRoomGames::Spades::Scoring.new(six_players, "team_size" => 3)
assert(triples.unit_ids == ["team:0", "team:1"], "six-player triples did not create two teams")
assert(triples.members_for("team:0") == ["Alice", "Carol", "Eve"], "the first team of three has wrong seats")
assert(triples.members_for("team:1") == ["Bob", "Dave", "Frank"], "the second team of three has wrong seats")

manual_teams = GameRoomGames::Spades::Scoring.new(
  players,
  "team_size" => 2,
  GameRoomTeams::OPTION_KEY => [0, 0, 1, 1]
)
assert(manual_teams.members_for("team:0") == ["Alice", "Bob"], "Spades ignored a manual first team")
assert(manual_teams.members_for("team:1") == ["Carol", "Dave"], "Spades ignored a manual second team")

session = spades_session("partnership" => true)
empty = game.replay(session, [], repository)
context = GameRoomGames::ActionContext.new(
  session_id: 1,
  table_id: 1,
  random_source: GameRoomRandom::SequenceSource.new((1..16).to_a),
  now: 1
)
automatic = game.automatic_action(empty, "Alice", context: context)
status, deal_plan = game.action_for(automatic, empty, "Alice", context: context)
assert(status == :ok, "the table owner could not deal the cards")
deal_command = deal_plan.events.first
events = [spades_event(1, "Alice", deal_command.action, deal_command.value)]
dealt = game.replay(session, events, repository)
hands = dealt.state[:hands]
assert(dealt.state[:phase] == :bidding, "the first deal did not start bidding")
assert(hands.values.all? { |hand| hand.length == 13 }, "four-player hands do not contain 13 cards")
assert(hands.values.flatten.uniq.length == 52, "the deal contains missing or duplicate cards")

no_hell_session = spades_session("partnership" => false, "no_hell" => true)
no_hell_events = [spades_event(1, "Alice", "deal", "1|0|000102030405060708090a0b0c0d0e0f")]
[["Bob", 3], ["Carol", 4], ["Dave", 3]].each_with_index do |(actor, bid), index|
  no_hell_events << spades_event(index + 2, actor, "bid", bid)
end
no_hell_replay = game.replay(no_hell_session, no_hell_events, repository)
last_bids = game.legal_actions(no_hell_replay, "Alice").map { |action| action["bid"] }
assert(!last_bids.include?(3), "No hell allowed the final bids to equal the number of tricks")
assert(last_bids.include?(2) && last_bids.include?(4), "No hell removed legal neighboring bids")

play_events = [spades_event(1, "Alice", "deal", "1|0|000102030405060708090a0b0c0d0e0f")]
[["Bob", 1], ["Carol", 1], ["Dave", 1], ["Alice", 1]].each_with_index do |(actor, bid), index|
  play_events << spades_event(index + 2, actor, "bid", bid)
end
before_play = game.replay(session, play_events, repository)
opening_actions = game.legal_actions(before_play, "Bob")
assert(opening_actions.none? { |action| action["card"].end_with?("S") }, "spades may be led before they are broken")

carol_hand = before_play.state[:hands]["Carol"]
lead = opening_actions.find do |action|
  carol_hand.any? { |card| card.end_with?(action["card"][-1]) }
end
assert(lead != nil, "the deterministic deal did not provide a follow-suit test case")
play_events << spades_event(6, "Bob", "play", lead["card"])
after_lead = game.replay(session, play_events, repository)
responses = game.legal_actions(after_lead, "Carol").map { |action| action["card"] }
assert(
  responses.all? { |card| card.end_with?(lead["card"][-1]) },
  "a player was allowed to ignore the led suit"
)

lone_ace_state = {
  players: players,
  phase: :playing,
  current_player: "Alice",
  hands: { "Alice" => %w[AS 3H 4D] },
  current_trick: [{ player: "Bob", card: "2S" }],
  spades_broken: true
}
assert(
  game.send(:legal_cards, lone_ace_state, "Alice").sort == %w[AS 3H 4D].sort,
  "a lone ace of spades still forces the player to follow a spade lead"
)
assert(
  game.send(:spades_round_planner).send(
    :observed_legal_cards,
    %w[AS 3H 4D],
    [{ player: "Bob", card: "2S" }],
    true
  ).sort == %w[AS 3H 4D].sort,
  "the round planner did not recognize the lone-ace exception"
)

multiple_spades_state = Marshal.load(Marshal.dump(lone_ace_state))
multiple_spades_state[:hands]["Alice"] = %w[AS 3S 4D]
assert(
  game.send(:legal_cards, multiple_spades_state, "Alice").sort == %w[AS 3S].sort,
  "the lone-ace exception was applied while another spade remained"
)

only_ace_state = Marshal.load(Marshal.dump(lone_ace_state))
only_ace_state[:hands]["Alice"] = %w[AS]
assert(
  game.send(:legal_cards, only_ace_state, "Alice") == %w[AS],
  "the last ace of spades was not playable as the final card"
)

ordinary_follow_state = Marshal.load(Marshal.dump(lone_ace_state))
ordinary_follow_state[:hands]["Alice"] = %w[AS 3H 4D]
ordinary_follow_state[:current_trick] = [{ player: "Bob", card: "2H" }]
assert(
  game.send(:legal_cards, ordinary_follow_state, "Alice") == %w[3H],
  "the lone-ace exception incorrectly disabled following another suit"
)

surface = game.surface_spec(after_lead, "Carol")
assert(surface.is_a?(GameSurfaces::CardTableSpec), "the active hand is not rendered as a card table")
assert(surface.zones.map(&:id) == ["hand"], "cards on the table still occupy a separate Tab field")
assert(surface.zones.first.header == "Your hand", "the hand field still contains a full game report")
view = game.game_view_spec(after_lead, "Carol")
assert(view.is_a?(GameRoomLayout::ViewSpec), "Spades bypasses the shared game layout")
assert(view.sections == [:status, :game, :chat, :history, :users], "Spades changed the shared field order")
shortcuts = game.game_shortcuts(after_lead, "Carol").each_with_object({}) do |shortcut, result|
  result[[shortcut.key, shortcut.modifiers.to_a]] = shortcut
end
assert(shortcuts[["s", []]].message.include?("Scores:"), "the score shortcut is missing")
assert(!shortcuts[["s", []]].message.include?("bags"), "bags are still presented as a separate score field")
assert(shortcuts[["h", []]].message.include?("Your hand:"), "the shared hand shortcut is missing")
assert(shortcuts[["b", []]].message.include?("Alice: 1"), "the bids shortcut is incomplete")
assert(shortcuts[["c", []]].message.include?("Bob:"), "plain C no longer reads the cards on the table")
table_cards_list = shortcuts[["c", [:control]]]
assert(table_cards_list.kind == :browse, "Ctrl+C does not open the cards-on-table list")
assert(table_cards_list.prompt == "Cards on the table", "the Ctrl+C card list has the wrong header")
assert(table_cards_list.choices.map(&:label).any? { |label| label.include?("Bob:") }, "the Ctrl+C card list is incomplete")
assert(shortcuts[["f", []]].message.include?("led suit"), "the led-suit shortcut is missing")
assert(shortcuts[["v", []]].message.include?("Alice: 0/1"), "V does not report Alice's tricks against her bid")
assert(shortcuts[["v", []]].message.include?("Carol: 0/1"), "V does not report the viewer's tricks against their bid")
assert(shortcuts[["i", []]].message.include?("Carol: 0/1"), "I does not report the viewer's tricks against their bid")
assert(!shortcuts[["i", []]].message.include?("Alice: 0/1"), "I still duplicates the all-player round summary")
assert(shortcuts[["t", []]].message.include?("Carol"), "the turn shortcut names the wrong player")

bidding_shortcuts = game.game_shortcuts(no_hell_replay, "Alice").each_with_object({}) do |shortcut, result|
  result[shortcut.key] = shortcut
end
bid_shortcut = bidding_shortcuts["b"]
assert(bid_shortcut.kind == :number_input, "B does not open numeric bid entry on the bidder's turn")
assert(bid_shortcut.action_name == "bid", "the bid shortcut emits the wrong action")
assert(!bid_shortcut.allowed_values.include?(3), "the bid shortcut ignored No Hell validation")
assert(bid_shortcut.allowed_values.include?(2), "the bid shortcut omitted a legal bid")

round_events = [spades_event(1, "Alice", "deal", "1|0|000102030405060708090a0b0c0d0e0f")]
loop do
  round_replay = game.replay(session, round_events, repository)
  break if round_replay.state[:phase] == :round_complete

  actor = round_replay.current_player
  action = game.legal_actions(round_replay, actor).first
  assert(action != nil, "a player had no legal action during a live round")
  status, plan = game.action_for(action, round_replay, actor)
  assert(status == :ok, "a legal Spades action was rejected during a full round")
  command = plan.events.first
  round_events << spades_event(round_events.length + 1, actor, command.action, command.value)
  assert(round_events.length < 100, "a Spades round did not terminate")
end
completed = game.replay(session, round_events, repository)
assert(completed.state[:hands].values.all?(&:empty?), "a completed round still contains cards")
assert(completed.state[:tricks].values.sum == 13, "a four-player round did not contain 13 tricks")
assert(completed.state[:scores].values.any? { |score| score != 0 }, "the completed round was not scored")

puts "Spades model tests passed"
