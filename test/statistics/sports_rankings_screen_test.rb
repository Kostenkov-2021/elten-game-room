require_relative '../support/quiz_creator_native'
require_relative '../support/native_tasks'
require EltenTestHost.file('src/ui/controls/table_box.rb')
Object.const_set(:TableBox, EltenAPI::Controls.const_get(:TableBox)) unless Object.const_defined?(:TableBox)
require_relative '../../lib/sports_rankings/screen'

GameRoomLocalization.boot(host_language: 'en', settings: {'interface_language'=>'en'})
module Session
  def self.name; @sports_user || 'Alice'; end
  def self.sports_user=(value); @sports_user=value; end
end
module GameRoomClock
  def self.synchronize; true; end
end

def sports_frame(form)
  EltenAPI::KeyboardState.update(raw_state: "\0"*256, events: [], now: Process.clock_gettime(Process::CLOCK_MONOTONIC))
  $input_frame_serial = $input_frame_serial.to_i + 1
  $keyboard_state_frame_serial, $keyboard_state_frame_thread = $input_frame_serial, Thread.current
  $activecontrols = []
  form.update
end

game = Struct.new(:id, :name).new('axel_pong', 'Axel Pong')
runtime = TestTaskRuntime.new('sports-ranking-ui')
program = Object.new
program.class.define_singleton_method(:app_runtime) { runtime }
ui, calls = Thread.current, []
row = {'place'=>1,'user'=>'Alice','won'=>4,'lost'=>2,'scored'=>45,'conceded'=>31,'points'=>2.83}
store = Object.new
store.define_singleton_method(:report) do |**options|
  raise 'Ranking network read ran on UI thread' if Thread.current == ui
  calls << options
  [row.dup]
end
screen = GameRoomSportsRankings::Screen.new(program:program,game:game,
  service:Struct.new(:store).new(store),today:-> {Date.new(2026,10,24)})
screen.instance_variable_set(:@mode,'singles')
details_seen = false
Form.driver = lambda do |form|
  field = form.fields.first
  if field.is_a?(TableBox)
    Timeout.timeout(5) { loop { sports_frame(form); break unless field.rows.empty?; Thread.pass } }
    assert(field.rows == [['1','Alice']], 'Leaderboard exposed points or whole statistics on its rows')
    form.index = 0
    form.accept_button.trigger(:press)
    assert(details_seen, 'Enter on a player did not open statistics')
    form.fields[1].trigger(:press)
    Timeout.timeout(5) { loop { sports_frame(form); break if calls.size == 2 && !screen.instance_variable_get(:@work).busy?; Thread.pass } }
    assert(calls.last[:fresh], 'Explicit Refresh reused the old ranking snapshot')
    form.cancel_button.trigger(:press)
  else
    assert(field.is_a?(EditBox) && (field.flags & EditBox::Flags::ReadOnly) != 0, 'Player statistics are not read-only text')
    assert(field.text.lines.size == 6 && field.text.include?('Matches won: 4') && field.text.include?('Goal balance: 14'), 'Detailed statistics omit a requested counter')
    assert(!field.text.include?('2.83') && !field.text.include?('Ranking points'), 'Internal ranking points were displayed')
    details_seen = true
    form.cancel_button.trigger(:press)
  end
end
begin
  Programs.with_runtime(runtime) { screen.send(:show_results,1,'Last 7 days') }
  assert(calls.first.values_at(:from_day,:to_day)==[20261018,20261024], 'Seven-day period is not inclusive')
  assert(screen.send(:range,3,Date.new(2026,10,24))==[20260425,20261024], 'Six-month calendar period differs')

  # An account change cancels a pending read without waiting for the server.
  gate, entered = Queue.new, Queue.new
  store.define_singleton_method(:report) do |**options|
    entered << options[:cancellation_token]
    gate.pop
    [row.dup]
  end
  Form.driver = lambda do |form|
    form.instance_variable_set(:@wait,true)
    token = Timeout.timeout(5) { entered.pop }
    Session.sports_user = 'Bob'
    sports_frame(form)
    assert(!form.instance_variable_get(:@wait), 'Account change left the old ranking open')
    form.cancel_button.trigger(:press)
    gate << true
    @token = token
  end
  Programs.with_runtime(runtime) { screen.send(:show_results,1,'Last 7 days') }
  assert(@token.cancelled?, 'Closed ranking did not cancel the pending request')
ensure
  Session.sports_user = 'Alice'
  gate << true if gate
  runtime.close
end
puts 'PASS sports ranking native view: place/nickname rows, six statistics, hidden score, periods, background Refresh and account cancellation'
