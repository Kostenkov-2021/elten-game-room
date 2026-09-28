binary_screen_run = nil
if ARGV.first || ENV["BATTLESHIP_BINARY_SOURCE"] == "1"
  require_relative "binary_rules_load"
  binary_screen_run = GameScreen.instance_method(:run)
else
  require_relative "ui"
  require_relative "../../lib/game_surfaces"
  require_relative "../../lib/game_screen"
  require_relative "../../games/battleship"
end
require_relative "native_room_harness"
require_relative "log"

module EltenAPI::Tasks
  class Cancelled < StandardError; end unless const_defined?(:Cancelled)
  class CancellationToken
    def cancel; @cancelled = true; end
    def cancelled?; @cancelled == true; end
    def raise_if_cancelled!; raise Cancelled if cancelled?; end
  end unless const_defined?(:CancellationToken)
  def self.run(**options)
    token = options[:cancellation_token] || CancellationToken.new
    yield nil, token
  end
end

class FormTimer
  def initialize(_interval, repeat:, &callback); @callback = callback; end
  def fire; @callback.call; end
end
class Form
  class << self; attr_accessor :driver; end
  def wait; Form.driver.call(self); end
  def keyboard_idle_frame?; true; end
  def resume; end
end

class BattleshipClip
  attr_accessor :done
  attr_reader :name, :volume, :closed
  def initialize(name, volume:); @name, @volume = name, volume; end
  def length; 4.0; end
  def finished?; @done || @closed; end
  def close; @closed = true; end
end
