require_relative 'native_room_harness'
require_relative 'audio_ball_client'
require_relative '../../games/four_in_a_row'

# In-memory native-session broker and clocked UI peripherals. The production
# GameScreen#run, repository writes, replay, timers and clients are not replaced.
module EltenAPI::Tasks
  class Cancelled < StandardError; end unless const_defined?(:Cancelled)
  class CancellationToken
    def cancelled?; false; end
    def raise_if_cancelled!; end
    def cancel(*_args); end
  end
  def self.run(**options)
    options[:ui].update if options[:ui].respond_to?(:update)
    yield nil, options[:cancellation_token] || CancellationToken.new
  end
end

class FormTimer
  def initialize(interval, repeat: false, autostart: true, &block)
    @interval, @repeat, @block = interval, repeat, block
    @due = $help_clock + interval if autostart
  end
  def update
    return unless @due && $help_clock >= @due
    @due = @repeat ? $help_clock + @interval : nil
    @block.call
  end
end
class FakeControl
  def key_held?(_key); false; end
  def key_pressed?(_key); false; end
end
class Form
  class << self; attr_accessor :driver; end
  def wait
    @wait = true
    while @wait
      $help_clock += 0.016
      $help_frames += 1
      raise 'Game did not progress while help was open' if $help_frames > 5000
      Form.driver.call(self)
      update
      Thread.pass # The real session worker, not a synchronous UI bot, must run.
    end
  end
  def update
    $activecontrols = [self]
    fields[index.to_i]&.update
    @timers.to_a.dup.each(&:update)
  end
  def resume; @wait = false; end
  def focus(*_args); fields[index.to_i]&.focus; end
  def keyboard_idle_frame?; true; end
end

def screen_fixture(game, bots: 0)
  $help_clock, $help_frames = 0.0, 0
  $game_room_test_user = 'Alice' # Host identity also exists on the managed worker.
  h = NativeRoomHarness.new(game: game, users: bots > 0 ? ['Alice'] : %w[Alice Bob], bots: bots)
  h.start
  sync = GameRoomSync::Controller.new(transport: h.transports['Alice'], table_id: h.table['__id'],
    session_id: h.session['__id'], clock: -> { $help_clock })
  screen = GameScreen.new(program: ProgramDouble.new(h.broker.endpoint('Alice')),
    repository: h.repositories['Alice'], game: game, session: h.session,
    table: h.table, table_owner: 'Alice', synchronizer: sync,
    game_services: {transport: h.transports['Alice']},
    room_snapshot_provider: -> {
      data = h.transports['Alice'].room_snapshot(h.table)
      data && LobbyRepository::TableSnapshot.new(**data)
    })
  screen.define_singleton_method(:alert) { |text| raise "Unexpected alert: #{text}" }
  screen.define_singleton_method(:monotonic_time) { $help_clock }
  [h, screen]
end
