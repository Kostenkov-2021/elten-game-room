require_relative "../../support/pong_client"

class NoPointerBackend
  def sample; nil; end
  def suspend; nil; end
end

def sample_state(client, field, form)
  {
    focus: form.index == 1 ? 'chat' : 'playfield',
    field: field.input.dup,
    pointer_key_count: client.instance_variable_get(:@pointer_key_count),
    pointer_press: client.instance_variable_get(:@pointer_press),
    raw_press: client.instance_variable_get(:@raw_press),
    total_press: client.instance_variable_get(:@total_press),
    paused: client.paused,
    turn: client.engine.turn,
    ball: client.engine.ball.dup
  }
end

def run_case(old_press:, task:)
  h = PongHarness.new(players: ['Alice', 'bot:1:1'], viewers: ['Alice'])
  client = h.clients.fetch('Alice')
  client.instance_variable_set(:@mouse,
    GameRoomPong::MouseControl.new(backend: NoPointerBackend.new))
  surface = GameSurfaces.build(h.rules.surface_spec(h.replay, 'Alice'))
  field, chat = surface.fields.first, EditBox.new('Chat')
  form = Form.new([field, chat])
  held, pressed = [], []
  field.define_singleton_method(:key_held?) { |key| held.include?(key) }
  field.define_singleton_method(:key_pressed?) { |key| pressed.include?(key) }
  client.attach_view(form, surface)
  $activecontrols = [form, field]
  states = {}

  # A real key tap in the initial readiness frame is deliberately consumed,
  # not served; later typing must not resurrect it.
  if old_press
    held << 0x26
    pressed << :key_up
  end
  field.update
  h.advance(1)
  held.clear
  pressed.clear
  field.update
  h.advance(4)
  states[:ready] = sample_state(client, field, form)
  assert(!client.paused && client.engine.turn.zero?, 'precondition: waiting for a human serve')

  field.blur
  form.index = 1
  $activecontrols = [form, chat]
  chat.text = 'A test message, with spaces'
  h.advance(1)
  states[:chat_before_task] = sample_state(client, field, form)
  if task
    ui = client.network_task_ui(ui: task == :chat ? chat : :none,
      title: 'Sending chat message', show_after: 5, cancellation_token: nil)
    4.times { h.now += 0.016; ui.update }
    ui.close
  else
    h.advance(4)
  end
  states[:during_task] = sample_state(client, field, form)
  # No new Up, Space, Enter or mouse press; focus stays in chat.
  h.advance(1)
  states[:after_task] = sample_state(client, field, form)
  assert(held.empty? && pressed.empty?, 'probe accidentally generated fresh game input')
  assert(form.index == 1 && chat.text == 'A test message, with spaces', 'probe changed chat')
  # Returning focus alone must not serve; a genuinely new tap still must.
  deliberate_serve = nil
  if client.engine.turn.zero?
    form.index = 0
    $activecontrols = [form, field]
    field.focus
    field.update
    h.advance(2)
    assert(client.engine.turn.zero?, 'returning focus alone served')
    pressed << :key_up
    field.update
    pressed.clear
    field.update
    h.advance(1)
    deliberate_serve = client.engine.turn == 1
    assert(deliberate_serve, 'fresh quick released tap did not serve')
  end
  { old_press: old_press, task: task, states: states,
    spontaneous_serve: states[:chat_before_task][:turn].zero? && states[:after_task][:turn] == 1,
    deliberate_serve: deliberate_serve }
ensure
  h&.close
  $activecontrols = []
end

results = [false, true].flat_map do |old_press|
  [nil, :none, :chat].map { |task| run_case(old_press: old_press, task: task) }
end
assert(results.none? { |result| result[:spontaneous_serve] }, 'network work resurrected an old serve while typing in chat')
assert(results.all? { |result| result[:deliberate_serve] }, 'a fresh short tap after returning to the game was lost')
puts 'PASS Pong chat input: six stale/empty-counter and no-task/chat-task/progress-task cases; fresh serve preserved'
