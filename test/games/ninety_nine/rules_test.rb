require_relative "../../../lib/game_surfaces/specifications"
require_relative "../../support/sequence_random"

def _(text)
  text
end

def n_(singular, plural, count)
  count.to_i == 1 ? singular : plural
end


require "json"
require_relative "../../../lib/game_random"
require_relative "../../../games/base"
require_relative "../../../games/ninety_nine"

class NinetyNineRepository
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

def ninety_event(id, actor, action, value = "")
  { "id" => id, "actor" => actor, "action" => action, "value" => value.to_s }
end

players = ["Alice", "Bob", "Carol"]
game = GameRoomGames::NinetyNine.new
repository = NinetyNineRepository.new(players)
session = { "options" => JSON.generate(game.default_options) }

assert(game.minimum_players == 2 && game.maximum_players == 8, "Ninety-nine exposes the wrong player range")
assert(game.supports_bots?, "Ninety-nine does not support shared bots")
assert(game.default_options["starting_tokens"] == 9, "Ninety-nine has the wrong default token count")
playroom_hand = %w[0AS 02H 0AC 0TC 02S 12C 0AH 02C 02D].sort_by do |card|
  game.send(:card_sort_key, card)
end
assert(
  playroom_hand == %w[02H 0AH 02S 0AS 02D 02C 12C 0TC 0AC],
  "Ninety-nine does not use the shared low-to-high Playroom card order"
)

assert(game.send(:total_after_card, 25, "09C", "normal") == 25, "nine did not leave the total unchanged")
assert(game.send(:total_after_card, 25, "0TC", "plus") == 35, "ten did not add ten")
assert(game.send(:total_after_card, 25, "0TC", "minus") == 15, "ten did not subtract ten")
assert(game.send(:total_after_card, 5, "0TC", "minus") == 0, "ten allowed a negative pile total")
assert(game.send(:total_after_card, 25, "0AC", "one") == 26, "ace did not add one")
assert(game.send(:total_after_card, 25, "0AC", "eleven") == 36, "ace did not add eleven")
assert(game.send(:total_after_card, 48, "02C", "normal") == 96, "two did not double a low even total")
assert(game.send(:total_after_card, 52, "02C", "normal") == 26, "two did not halve an even total above 49")
assert(game.send(:total_after_card, 53, "02C", "normal") == 106, "two did not double an odd total")

deal = ninety_event(1, "Alice", "deal", "1|0|000102030405060708090a0b0c0d0e0f")
dealt = game.replay(session, [deal], repository)
assert(dealt.state[:phase] == :playing, "the first deal did not start the round")
assert(dealt.state[:hands].values.all? { |hand| hand.length == 3 }, "the deal did not give three cards to every player")
assert(dealt.current_player == "Bob", "the player left of the dealer did not start")
assert(dealt.state[:draw_pile].length == 43, "the draw pile has the wrong size")

play_selection = game.legal_actions(dealt, "Bob").first
status, play_plan = game.action_for(play_selection, dealt, "Bob")
assert(status == :ok, "a legal Ninety-nine card was rejected")
events = [deal]
play_plan.events.each_with_index do |command, index|
  events << ninety_event(index + 2, "Bob", command.action, command.value)
end
played = game.replay(session, events, repository)
assert(play_plan.events.map(&:action) == %w[play_draw], "a normal play and its automatic draw were not atomic")
assert(played.state[:phase] == :playing, "automatic drawing did not advance the turn")
assert(played.current_player != "Bob", "automatic drawing did not pass the turn")
assert(played.state[:hands]["Bob"].length == 3, "automatic drawing did not restore a three-card hand")
assert(!played.history.any? { |entry| entry.kind == :draw }, "an automatic replacement draw was announced")
assert(played.history.any? { |entry| entry.kind == :play && entry.text.include?("Pile:") }, "a play did not use the concise pile announcement")

terminal_state = game.send(:initial_state, players, game.default_options)
terminal_state[:phase] = :playing
terminal_state[:current_player] = "Bob"
terminal_state[:total] = 98
terminal_state[:hands]["Bob"] = ["0AC"]
terminal_replay = GameRoomGames::Replay.new(players: players, current_player: "Bob", winner: nil, draw: false, state: terminal_state)
status, terminal_plan = game.action_for(
  { "kind" => "card", "action" => "select", "card" => "0AC|one" },
  terminal_replay,
  "Bob"
)
assert(status == :ok && terminal_plan.events.map(&:action) == ["play"], "a replacement card was drawn after reaching 99")

def controlled_state(game, players)
  options = game.default_options
  state = game.send(:initial_state, players, options)
  state[:phase] = :playing
  state[:dealer_index] = 0
  state[:current_player] = "Bob"
  state[:seed] = "00" * 16
  state
end

history = []
state = controlled_state(game, players)
state[:total] = 53
state[:hands]["Bob"] = ["02C"]
applied = game.send(
  :apply_play,
  state,
  ninety_event(10, "Bob", "play", "02C|normal"),
  "Bob",
  repository,
  history
)
assert(applied, "the official 53-to-106 example was rejected")
assert(state[:total] == 106, "the official two-card example has the wrong total")
assert(state[:tokens]["Bob"] == 6, "crossing 66 and exceeding 99 did not cost three tokens")
assert(state[:phase] == :round_complete, "exceeding 99 did not end the round")

history = []
state = controlled_state(game, players)
state[:total] = 30
state[:hands]["Bob"] = ["03C"]
game.send(:apply_play, state, ninety_event(11, "Bob", "play", "03C|normal"), "Bob", repository, history)
assert(state[:tokens]["Alice"] == 8 && state[:tokens]["Carol"] == 8, "reaching 33 did not charge every other player")
assert(state[:tokens]["Bob"] == 9, "the player reaching 33 was charged")

history = []
state = controlled_state(game, players)
state[:total] = 43
state[:hands]["Bob"] = ["0TC"]
game.send(:apply_play, state, ninety_event(12, "Bob", "play", "0TC|minus"), "Bob", repository, history)
assert(state[:total] == 33, "a 10 subtracting from 43 did not reduce to 33")
assert(state[:tokens]["Alice"] == 9 && state[:tokens]["Bob"] == 9 && state[:tokens]["Carol"] == 9, "reaching 33 by subtraction should not charge anyone")

history = []
state = controlled_state(game, players)
state[:total] = 76
state[:hands]["Bob"] = ["0TC"]
game.send(:apply_play, state, ninety_event(13, "Bob", "play", "0TC|minus"), "Bob", repository, history)
assert(state[:total] == 66, "a 10 subtracting from 76 did not reduce to 66")
assert(state[:tokens]["Alice"] == 9 && state[:tokens]["Bob"] == 9 && state[:tokens]["Carol"] == 9, "reaching 66 by subtraction should not charge anyone")

history = []
state = controlled_state(game, players)
state[:total] = 33
state[:hands]["Bob"] = ["02C"]
game.send(:apply_play, state, ninety_event(14, "Bob", "play", "02C|normal"), "Bob", repository, history)
assert(state[:total] == 66, "doubling 33 did not become 66")
assert(state[:tokens]["Alice"] == 8 && state[:tokens]["Bob"] == 9 && state[:tokens]["Carol"] == 8, "reaching 66 by doubling did not charge every other player")

history = []
state = controlled_state(game, players)
state[:total] = 33
state[:hands]["Bob"] = ["09C"]
game.send(:apply_play, state, ninety_event(15, "Bob", "play", "09C|normal"), "Bob", repository, history)
assert(state[:total] == 33, "a 9 changed the pile total")
assert(state[:tokens]["Alice"] == 9 && state[:tokens]["Bob"] == 9 && state[:tokens]["Carol"] == 9, "leaving the total at 33 should not charge anyone")

history = []
state = controlled_state(game, players)
state[:total] = 66
state[:hands]["Bob"] = ["02C"]
game.send(:apply_play, state, ninety_event(16, "Bob", "play", "02C|normal"), "Bob", repository, history)
assert(state[:total] == 33, "playing a 2 at 66 did not reduce the total to 33")
assert(state[:tokens]["Alice"] == 9 && state[:tokens]["Bob"] == 9 && state[:tokens]["Carol"] == 9, "reaching 33 by halving should not charge anyone")

history = []
state = controlled_state(game, players)
state[:hands]["Bob"] = ["04C"]
game.send(:apply_play, state, ninety_event(17, "Bob", "play", "04C|normal"), "Bob", repository, history)
assert(state[:direction] == -1, "four did not reverse the direction")
assert(state[:pending_player] == "Alice", "reversed play selected the wrong next player")

history = []
state = controlled_state(game, players)
state[:hands]["Bob"] = ["0JC"]
game.send(:apply_play, state, ninety_event(18, "Bob", "play", "0JC|normal"), "Bob", repository, history)
assert(state[:pending_player] == "Alice", "jack did not skip the next player")

history = []
state = controlled_state(game, players)
state[:tokens]["Bob"] = 3
state[:hands]["Bob"] = []
game.send(:apply_no_cards, state, ninety_event(19, "Bob", "no_cards"), "Bob", repository, history)
assert(state[:tokens]["Bob"] == 0 && !state[:eliminated]["Bob"], "a player paying their last tokens was eliminated too early")

state = controlled_state(game, players)
state[:tokens]["Bob"] = 0
game.send(:charge_player, state, "Bob", 1, 20, [], "test")
assert(state[:eliminated]["Bob"], "a player unable to pay was not eliminated")

state = controlled_state(game, players)
state[:phase] = :awaiting_draw
state[:current_player] = "Bob"
bot_actions = game.legal_actions(
  GameRoomGames::Replay.new(current_player: "Bob", winner: nil, draw: false, state: state),
  "Bob"
)
chosen = game.bot_strategy.choose(
  actions: bot_actions,
  observation: nil,
  actor: "Bob",
  random_source: GameRoomRandom::SequenceSource.new([1])
)
assert(chosen["action"] == "draw", "the Ninety-nine bot deliberately forgot to draw")

state = controlled_state(game, players)
state[:total] = 25
state[:hands]["Bob"] = ["0TC", "0AC"]
replay = GameRoomGames::Replay.new(
  players: players,
  current_player: "Bob",
  winner: nil,
  draw: false,
  state: state
)
surface = game.surface_spec(replay, "Bob")
cards = surface.zones.first.cards
assert(cards.length == 2, "flexible tens and aces are displayed as duplicate cards")
ten = cards.find { |card| card.id == "0TC" }
ace = cards.find { |card| card.id == "0AC" }
assert(ten.choices.map(&:label) == ["Add 10", "Subtract 10"], "the ten choices are incomplete")
assert(ace.choices.map(&:label) == ["Add 1", "Add 11"], "the ace choices are incomplete")

state[:total] = 5
low_replay = GameRoomGames::Replay.new(
  players: players,
  current_player: "Bob",
  winner: nil,
  draw: false,
  state: state
)
low_surface = game.surface_spec(low_replay, "Bob")
low_ten = low_surface.zones.first.cards.find { |card| card.id == "0TC" }
assert(low_ten.choices == nil, "subtracting below zero is still offered in the hand")
status, = game.action_for(
  { "kind" => "card", "action" => "select", "card" => "0TC|minus" },
  low_replay,
  "Bob"
)
assert(status == :invalid_card_choice, "subtracting below zero was accepted")

shortcuts = game.game_shortcuts(replay, "Bob").select { |shortcut| shortcut.modifiers.empty? }
  .each_with_object({}) { |shortcut, result| result[shortcut.key] = shortcut }
assert(shortcuts["c"].message == "Pile: 5.", "C does not use the concise pile announcement")
assert(!shortcuts["s"].message.include?("tokens"), "S still reads the redundant token unit")
assert(shortcuts["s"].message.include?("Bob 9"), "S does not announce a player's score")
assert(shortcuts["h"].message.include?("10 of clubs"), "H does not announce numeric card ranks with digits")
assert(shortcuts["t"] != nil, "T is missing from Ninety-nine")

puts "Ninety-nine model tests passed"
