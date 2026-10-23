require_relative '../support/tournament_native'
require_relative '../support/native_background_capacity'
require_relative '../../lib/tournaments/local_fixed_team_execution_screen'
require_relative '../../lib/tournaments/local_realtime_game_dialog'
include GameRoomTest::Assertions

T = GameRoomTournaments
Status = Struct.new(:value) do
  def set_text(value); self.value = value; end
end
Control = Struct.new(:index)
FormSnapshot = Struct.new(:index, :fields)
CurrentContext = Struct.new(:value) do
  def current?(_lease); value; end
end

# These are the actual local-tool start methods and real Tasks/Work limits.
# Only their already-captured UI selection and local controller are fixtures;
# native modal behavior is covered by the separate existing UI scripts.
failures = []
%i[readiness fixed realtime].each do |kind|
  GameRoomTest::NativeBackgroundCapacity.with(128) do |work, free_capacity, runtime|
    calls = []
    operation_entered, operation_release = Queue.new, Queue.new
    program_class = Class.new do
      class << self; attr_accessor :app_runtime; end
    end
    program_class.app_runtime = runtime
    controller = Object.new
    controller.define_singleton_method(:view) { {matches: [{'match_id' => 'fixture-match'}]} }
    controller.define_singleton_method(:readiness) do |**input|
      calls << input; operation_entered << true; operation_release.pop
      :readiness_result
    end
    controller.define_singleton_method(:perform) do |**input|
      calls << input; operation_entered << true; operation_release.pop
      {local_game: {state: :blocked}}
    end
    klass = case kind
    when :readiness then T::MatchEntryScreen
    when :fixed then T::LocalFixedTeamExecutionScreen
    when :realtime then T::MatchEntryScreen::RealtimeGame
    end
    window = klass.allocate
    window.instance_variable_set(:@program, program_class.new)
    window.instance_variable_set(:@controller, controller)
    window.instance_variable_set(:@form, FormSnapshot.new(0, []))
    window.instance_variable_set(:@status, Status.new('original'))
    window.instance_variable_set(:@matches, Control.new(0))
    window.instance_variable_set(:@windows, Control.new(0))
    window.instance_variable_set(:@readiness_work, work)
    window.instance_variable_set(:@work, work)
    window.instance_variable_set(:@context, CurrentContext.new(true))
    window.instance_variable_set(:@lease, Object.new)
    window.define_singleton_method(:current?) { true }
    window.define_singleton_method(:selected_id) { 'fixture-tournament' }
    window.define_singleton_method(:selectors) { {intent_id: 'fixture-tournament'}.freeze }
    window.define_singleton_method(:local_readiness_refusal) { nil }
    window.define_singleton_method(:local_readiness_status) { 'local readiness' }
    window.define_singleton_method(:status_text) { 'local execution' }
    case kind
    when :readiness then window.send(:start_readiness, :inspect)
    when :fixed then window.send(:start_fixed, :catalog)
    when :realtime then window.send(:begin_work, action: :local_game_move, operation_id: 'one-original-intent')
    end
    assert(calls.empty?, "#{kind} bypassed native capacity")
    pending = window.instance_variable_get(kind == :realtime ? :@pending : :@readiness_pending)
    assert(pending, "#{kind} discarded an unstarted local intention")
    assert_equal(false, window.send(:admit_pending_work))
    tick = {readiness: :drain_readiness, fixed: :drain_fixed, realtime: :advance_entry}.fetch(kind)
    3.times { window.send(tick) }
    assert(calls.empty?, "#{kind} update bypassed full capacity")
    free_capacity.call
    window.send(tick)
    Timeout.timeout(5) { operation_entered.pop }
    assert_equal(1, calls.size, "#{kind} ordinary update did not admit the original operation")
    operation_release << true
    wait_background_work(work)
    _value, error = work.take
    raise error if error
    assert_equal(1, calls.size, "#{kind} lost or repeated an admitted local operation")
    3.times { assert_equal(true, window.send(:admit_pending_work)) }
    assert_equal(1, calls.size, "#{kind} retried a completed operation")
    assert_equal(nil, window.instance_variable_get(:@work_admission))
  rescue StandardError => error
    failures << {case: kind, error: error.class.name, message: error.message}
  ensure
    operation_release << true if operation_release
  end
end

assert(failures.empty?, "Local UI native admission failures: #{failures.inspect}")

GameRoomTest::NativeBackgroundCapacity.with(128) do |work, free_capacity|
  abandoned = Class.new(StandardError)
  calls = []
  klass = Class.new(T::LocalTestDialogs::Window) do
    define_method(:build_form) do
      start_work_when_admitted(work) { calls << :not_allowed }
      raise abandoned, 'leave before admission'
    end
  end
  window = klass.new
  assert_raises(abandoned) { window.run }
  assert_equal(nil, window.instance_variable_get(:@work_admission), 'Closed local window retained its admission closure')
  free_capacity.call
  assert_equal([], calls, 'Leaving before admission started abandoned work')
end

puts 'PASS local-tool native admission: three actual start boundaries, untouched full4+128 limit, one original intent, no work before capacity and abandoned-window cleanup'
