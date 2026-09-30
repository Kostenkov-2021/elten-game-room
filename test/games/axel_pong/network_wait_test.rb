require_relative "../../support/pong_client"

class NetworkTestAudio < PongTestAudio
  attr_reader :goals, :points
  def initialize; super; @goals, @points = [], []; end
  def goal(**args); @goals << args; end
  def point(scores, **args); @points << [scores, args]; end
end

h = PongHarness.new
audio = h.clients.transform_values do |client|
  value = NetworkTestAudio.new
  client.instance_variable_set(:@audio, value)
  value
end
h.advance(220)
host = h.clients['Alice']
server_side = host.engine.server
h.press(h.players[server_side])
h.advance(8)
receiver_side = 1 - server_side
loser = h.clients[h.players[receiver_side]].engine
loser.ball.merge!('x' => 1.0, 'y' => receiver_side.zero? ? 0.5 : 19.5)
h.advance(10)
point = host.context_data['pong_point']
assert(point == "0:#{server_side}", 'miss did not reach mutual agreement')
assert(%w[Alice Bob].all? { |name| audio[name].goals.length == 1 }, 'goal waits for the LiveSessions write')
assert(audio.values.all? { |value| value.points.empty? }, 'uncommitted score was announced')
assert(h.replay.state[:scores] == [0, 0], 'early goal presentation changed the score')

# The game form is not running while Tasks.run reads/writes LiveSessions.
# Its optional UI adapter must continue heartbeats and audio, with no input.
host.detach_view
ui = host.network_task_ui(ui: :none, title: 'Saving', show_after: 5, cancellation_token: nil)
400.times do
  h.now += 0.016
  ui.update
  %w[Bob Watcher].each { |name| h.clients[name].frame }
end
assert(h.network.values.all? { |channel| channel.resets.zero? }, 'durable wait caused a false Communications outage')
assert(host.context_data['pong_point'] == point, 'durable wait lost the pending point')
assert(audio.values.all? { |value| value.points.empty? }, 'score announced before server confirmation')
assert(%w[Alice Bob].all? { |name| audio[name].goals.length == 1 }, 'goal duplicated during durable wait')
before = h.replay
h.accept_point(point)
event = { 'action' => 'pong_point' }
h.clients.each do |name, client|
  2.times { client.event(event, before, h.replay, name, h.repository) }
end
assert(h.replay.state[:scores].sum == 1, 'point counted more than once')
assert(audio.values.all? { |value| value.points.length == 1 }, 'confirmed score lost or duplicated')
assert(audio['Bob'].points.first[1][:goal_at].is_a?(Numeric), 'early goal was not deduplicated against replay')
assert((host.send(:rally_state).ready_at - h.now - 2.7).abs < 0.0001, 'durable write added a second goal pause')
ui.close
h.close

# Guests can see a committed point before the owner's read finishes. Fresh
# future-rally packets are heartbeats, but not permission for an early serve.
h = PongHarness.new
h.advance(220)
next_replay = h.rules.replay(h.session,
  [{'__id' => 1, 'actor' => 'Alice', 'action' => 'pong_point', 'value' => '0:0'}], h.repository)
%w[Bob Watcher].each { |name| h.clients[name].before_wait(next_replay, name) }
h.advance(400)
assert(h.network.values.all? { |channel| channel.resets.zero? }, 'adjacent-rally traffic looked like a broken connection')
h.clients['Alice'].before_wait(next_replay, 'Alice')
h.advance(8)
assert(h.clients.values.all?(&:paused), 'earlier durable read let a guest start before the owner')
h.advance(370)
assert(h.clients.values.none?(&:paused), 'shared serve readiness did not settle')
h.close

# A chat-only task while the original form is still attached must also keep
# the peer alive, but may not consume the same keys as Pong input.
h = PongHarness.new
h.advance(220)
host = h.clients['Alice']
surface = h.surfaces['Alice']
surface.define_singleton_method(:input) { |_form| raise 'network task read game keys' }
chat = Object.new
chat_updates = 0
chat.define_singleton_method(:update) { chat_updates += 1 }
ui = host.network_task_ui(ui: chat, title: 'Chat', show_after: 5, cancellation_token: nil)
400.times do
  h.now += 0.016
  ui.update
  %w[Bob Watcher].each { |name| h.clients[name].frame }
end
assert(chat_updates == 400 && h.network.values.all? { |channel| channel.resets.zero? }, 'chat-only task stopped the game channel')
ui.close
h.close

# Preserve the native task presentation contract: silent stays silent, an
# existing UI is updated, and the default delayed wait retains Escape/cleanup.
now, ticks, events = 0.0, 0, []
token = Object.new
token.define_singleton_method(:cancel) { |_error| events << :cancel }
module EltenAPI
  module Tasks
    class Cancelled < StandardError; end
  end
end unless defined?(EltenAPI::Tasks::Cancelled)
ui = GameRoomRealtime::TaskUI.new(ui: nil, title: 'Saving', show_after: 5,
  cancellation_token: token, clock: -> { now }, tick: -> { ticks += 1 })
ui.define_singleton_method(:modal_interaction_open) { events << :open }
ui.define_singleton_method(:modal_interaction_close) { events << :close }
ui.define_singleton_method(:waiting_opened) { false }
ui.define_singleton_method(:waiting) { events << :waiting }
ui.define_singleton_method(:waiting_end) { events << :end }
ui.define_singleton_method(:key_pressed?) { |_key| true }
ui.define_singleton_method(:play_sound) { |_sound| }
ui.update
assert(events.empty? && ticks == 1, 'short task opened a modal window')
now = 5.1
ui.update
ui.close; ui.close
assert(events == [:open, :waiting, :cancel, :end, :close], 'slow task lost cancellation or leaked modal state')

puts 'PASS Pong network waits: early agreed goal, authoritative score, no false outage, dedup, serve timing, UI/cancellation'
