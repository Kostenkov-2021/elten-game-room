require_relative "ui"
require_relative "../../lib/game_surfaces"
require_relative "new_games_fixture"
require_relative "elten_array_shuffle"
require_relative "../../games/ninety_nine"
require_relative "../../games/rummy"
require_relative "../../lib/game_screen"
require_relative "../../lib/hidden_submissions"
require_relative "../../lib/game_room_preferences"
require "digest"

module Session
  class << self; attr_accessor :name; end
end

def copy(value); Marshal.load(Marshal.dump(value)); end

def reshuffle_fixture(type, actor)
  game = type.new
  repo = NewGames116Repository.new([actor, "Bob", "Carol"])
  def repo.bot_turn_controller(_table_id); nil; end
  options = game.default_options.merge("thinking_time" => 0)
  options["variant"] = "draw" if game.id == "poker"
  session = { "options" => JSON.generate(options) }
  events = []
  start = game.replay(session, events, repo)
  start = append_action(game, session, repo, events, start, actor,
    { "kind" => "command", "action" => "deal" }, context_for)
  assert(start.history.none? { |entry| entry.kind == :reshuffle }, "#{game.id}: new deal falsely announces recycling")
  state = copy(start.state)
  state[:current_player] = actor
  case game.id
  when "uno", "makao"
    state[:discard] = state[:draw_pile] + state[:discard]
    state[:draw_pile] = []
    if game.id == "uno"
      state[:pending_draw] = 3
    else
      state[:draw_penalty] = 3
    end
    selection = { "action" => "draw" }
  when "ninety_nine"
    state[:discard] = state[:draw_pile]
    state[:draw_pile] = []
    probe = start.dup
    probe.state = state
    probe.current_player = actor
    selection = game.legal_actions(probe, actor).first
  when "rummy"
    state[:discard] = state[:stock]
    state[:stock] = []
    selection = { "action" => "draw" }
  when "poker"
    state[:phase] = :exchange
    state[:draw_discards] = state[:deck].drop(1)
    state[:deck] = state[:deck].first(1)
    selection = { "kind" => "card_packet", "action" => "exchange",
      "cards" => JSON.generate(state[:hands][actor].first(3)) }
  end
  # Start replay immediately before exhaustion instead of running hundreds
  # of turns. The real action, validation, recycling and replay remain used.
  game.define_singleton_method(:initial_state) { |*_args| copy(state) }
  [game, repo, session, state, selection]
end
