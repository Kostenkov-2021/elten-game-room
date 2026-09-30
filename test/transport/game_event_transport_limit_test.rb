require_relative "../support/ui"
require_relative "../../games/base"
require_relative "../../lib/game_screen"

def assert(condition, message)
  raise message if !condition
end

class GameRepository
  MAX_ACTION_LENGTH = 32 if !const_defined?(:MAX_ACTION_LENGTH)
  MAX_VALUE_LENGTH = 64 if !const_defined?(:MAX_VALUE_LENGTH)
end

module Log
  @transport_warnings = []

  class << self
    attr_reader :transport_warnings

    def warning(message)
      @transport_warnings << message.to_s
    end

    def debug(_message)
    end
  end
end

game = Object.new
game.define_singleton_method(:id) { "monopoly" }
screen = GameScreen.allocate
screen.instance_variable_set(:@game, game)
alerts = []
screen.define_singleton_method(:alert) { |message| alerts << message.to_s }

plan = lambda do |action, value|
  GameRoomGames::ActionPlan.new(events: [GameRoomGames::EventCommand.new(action: action, value: value)])
end

assert(screen.send(:action_plan_fits_transport?, plan.call("trade_offer", "x" * 64)),
  "an event exactly at the transport limit was rejected")
assert(!screen.send(:action_plan_fits_transport?, plan.call("trade_offer", "x" * 65)),
  "an oversized value passed the screen guard")
assert(alerts.last == "This action contains too much data and was not sent.",
  "an oversized human action has no controlled message")
assert(Log.transport_warnings.last.include?("game=monopoly") &&
  Log.transport_warnings.last.include?("action=trade_offer") &&
  Log.transport_warnings.last.include?("value_length=65") &&
  Log.transport_warnings.last.include?("value_limit=64"),
  "the diagnostic warning omits the game, action or value length")

alert_count = alerts.length
assert(!screen.send(:action_plan_fits_transport?, plan.call("a" * 33, ""), silent: true),
  "an oversized action name passed the screen guard")
assert(alerts.length == alert_count, "a silent automatic rejection interrupted the interface")
assert(Log.transport_warnings.last.include?("action_length=33") &&
  Log.transport_warnings.last.include?("action_limit=32"),
  "the diagnostic warning omits the action length")

puts "Game event transport limits: exact boundary, safe rejection and diagnostics passed"
