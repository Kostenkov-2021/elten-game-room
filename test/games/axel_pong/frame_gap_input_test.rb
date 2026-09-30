require_relative '../../support/pong_client'
require_relative '../../support/axel_pong_mouse'

# Exercise the production sampler AND physics scheduler. A delayed UI frame
# must discard pointer motion/time debt without restarting a held arrow.
class PongGapInputFixture
  attr_reader :position, :mouse, :backend, :client
  attr_accessor :active, :raw
  def initialize
    @now, @position, @active = 0.0, 15.0, true
    @raw = {'move' => -1, 'hit' => false, 'press' => 0, 'left_press' => 1, 'right_press' => 0}
    @backend = PongMouseBackend.new
    @mouse = GameRoomPong::MouseControl.new(backend: @backend)
    @client = GameRoomPong::Client.allocate
    @client.instance_variable_set(:@clock, -> { @now })
    @client.instance_variable_set(:@mouse, @mouse)
    @client.instance_variable_set(:@side, 0)
    @client.instance_variable_set(:@form, Object.new)
    surface = Object.new
    fixture = self
    surface.define_singleton_method(:input_active?) { |_form| fixture.active }
    @client.instance_variable_set(:@surface, surface)
  end
  def frame(seconds = 0.016, healthy: true)
    @now += seconds
    input = @client.send(:sample_pointer_input, @raw, healthy)
    count = 0
    @client.send(:each_physics_frame, @now) do |at|
      value = @mouse.step(input, position: @position, now_ms: (at * 1000).to_i)
      @position = value['paddle'] if value.key?('paddle')
      count += 1
    end
    @mouse.finish_frame
    count
  end
end

[0.065, 0.1, 0.12, 0.2, 0.3].each do |gap|
  (1..12).each do |phase|
    normal, delayed = PongGapInputFixture.new, PongGapInputFixture.new
    phase.times { normal.frame; delayed.frame }
    normal.frame
    assert(delayed.frame(gap) == 1, "#{gap}: caught up missed physics")
    12.times do |offset|
      assert(normal.position == delayed.position, "#{gap}/#{phase}/#{offset}: held repeat restarted")
      normal.frame; delayed.frame
    end
    assert(delayed.backend.suspends > normal.backend.suspends, 'mouse was not re-anchored')
    assert(delayed.mouse.clicks.zero?, 'gap created a click')
  end
end

[:inactive, :unhealthy, :settings, :network, :rally].each do |reason|
  run = PongGapInputFixture.new
  6.times { run.frame }
  before = run.position
  case reason
  when :inactive then run.active = false
  when :settings then run.client.instance_variable_set(:@settings_open, true)
  when :network then run.client.instance_variable_set(:@network_wait, true)
  when :rally then run.mouse.reset_rally
  end
  run.frame(0.12, healthy: reason != :unhealthy)
  assert(run.position == before, "#{reason}: background/reset moved paddle")
  run.active = true
  run.client.instance_variable_set(:@settings_open, false)
  run.client.instance_variable_set(:@network_wait, false)
  4.times { run.frame }
  assert(run.position == before, "#{reason}: repeat survived a real context change")
end

run = PongGapInputFixture.new
6.times { run.frame }
before = run.position
run.raw['move'] = 0
run.frame(0.12)
10.times { run.frame }
assert(run.position == before, 'released arrow moved after gap')
run.raw.merge!('move' => 1, 'right_press' => 1)
run.frame(0.12)
assert(run.position == before + 1, 'fresh reverse press did not move immediately')
100.times { run.frame }
assert(run.position == 29, 'paddle escaped table boundary')
puts 'PASS Pong gap input: 60 repeat phases, bounded physics, mouse re-anchor, context/rally resets, release/reversal/edge'
