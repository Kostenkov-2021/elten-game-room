require_relative "../support/background_help_game_screen"
require_relative "../support/assertions"
include GameRoomTest::Assertions

[:adapter, :snapshot, :none].each do |failure_at|
  layout = GameRoomLayout::Screen.new(view_spec: GameRoomLayout::ViewSpec.new)
  layout.session_id = 42
  layout.begin_bindings
  events = []
  fault = TypeError.new("cleanup failure: #{failure_at}")
  adapter = Object.new
  adapter.define_singleton_method(:close) do
    events << :adapter
    raise fault if failure_at == :adapter
  end
  client = Object.new
  client.define_singleton_method(:network_task_ui) { |**_| adapter }
  task = GameRoomNetworkTask.new
  result = task.run('Sending', layout: layout, table_id: 7, client: client,
    before_close: -> { events << :snapshot; raise fault if failure_at == :snapshot }) { :sent }
  assert_equal(:sent, result)
  assert(layout.form.game_room_pending_operation.active?, 'fixture did not gate the actual form')
  if failure_at == :none
    task.close
  else
    assert(assert_raises(TypeError) { task.close }.equal?(fault), 'cleanup lost its diagnostic')
  end
  assert(layout.form.game_room_pending_operation.nil?, 'cleanup failure permanently blocked the form')
  assert(layout.form.fields.all? { |field| field.game_room_activation_guard.nil? }, 'cleanup retained activation guards')
  task.close
  assert_equal([:adapter, :snapshot], events, 'cleanup was incomplete or repeated')
end
puts 'PASS network task cleanup: adapter/snapshot faults, restored activation and idempotent close'
