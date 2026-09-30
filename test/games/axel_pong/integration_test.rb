require_relative "../../support/pong_client"
require_relative "../../../lib/game_repository"

module Session
  def self.name; @name || 'Alice'; end
  def self.name=(value); @name = value; end
end

# Legacy screen submission boundary and GameRepository validation, with only
# the external LiveSessions call substituted. The managed runner's active
# point path is covered by pong_runner_point_snapshot_test.rb.
class PongPointTransport
  attr_reader :calls
  def initialize; @calls = []; end
  def live_store?; true; end
  def append_game_action(**args)
    @calls << args
    args[:events].each_with_index.map do |command, i|
      {'__id' => @calls.length * 10 + i, '__insertion_user' => Session.name,
       '__controller' => args[:controller], 'actor' => args[:actor],
       'action' => command.action, 'value' => command.value}
    end
  end
end
rules = GameRoomGames::AxelPong.new
[%w[Alice Bob], %w[Bob Carol], ['bot:7:1', 'bot:7:2']].each do |players|
  transport = PongPointTransport.new
  repository = GameRepository.new(Program.new, transport: transport, server_tables: {})
  session = {'__id' => 11, 'table_id' => 7, '__players' => players,
    '__insertion_user' => 'Alice', 'player_one' => players.first, 'options' => JSON.generate(rules.default_options)}
  replay = rules.replay(session, [], repository)
  context = GameRoomGames::ActionContext.new(table_owner: 'Alice', local_data: {'pong_point' => '0:0'})
  screen = GameScreen.allocate
  {game: rules, repository: repository, session: session, table_owner: 'Alice', table: {'__id' => 7}, pending_event_ids: []}.each do |key, value|
    screen.instance_variable_set("@#{key}", value)
  end
  screen.define_singleton_method(:action_context) { context }
  screen.define_singleton_method(:network_task) { |_title, **_options, &work| work.call }
  screen.define_singleton_method(:game_recipients) { ['Alice', *players.reject { |p| p.start_with?('bot:') }].uniq }
  assert(screen.send(:automatic_action_due?, replay), 'founder scheduler did not wake')
  assert(screen.send(:perform_automatic_action, replay), 'durable point not submitted')
  call = transport.calls.last
  assert(call[:actor] == players.first && call[:controller] == (players.first != 'Alice'), 'wrong authenticated controller route')
  assert(screen.instance_variable_get(:@pending_event_ids) == [10], 'point skipped pending-event confirmation')
  event = {'__id' => 10, '__insertion_user' => 'Alice', '__controller' => true, 'actor' => players.first,
    'action' => 'pong_point', 'value' => '0:0'}
  assert(rules.replay(session, [event, event], repository).state[:scores] == [1, 0], 'point accepted twice')
  assert(rules.replay(session, [event.merge('__insertion_user' => 'Mallory')], repository).state[:scores] == [0, 0], 'forged founder accepted')
  Session.name = 'Bob'
  assert(!screen.send(:automatic_action_due?, replay) && !screen.send(:perform_automatic_action, replay), 'guest became score authority')
  Session.name = 'Alice'
end

now = 0.0
network = {}
repository = Object.new
def repository.players_for(s); s['__players']; end
def repository.actor_of(e, _s); e['actor']; end
def repository.event_id(e); e['__id']; end
session = {'__players' => ['Alice', 'bot:7:1'], 'player_one' => 'Alice', 'options' => JSON.generate(rules.default_options)}
client = GameRoomPong::Client.new(Program.new, rules, clock: -> { now }, audio: PongTestAudio.new,
  channel_factory: ->(**args) { PongTestChannel.new(network, **args) })
client.bind_screen(session_id: 77, table_id: 7, owner: 'Alice', viewer: 'Alice', members: -> { ['Alice'] })
client.start
client.before_wait(rules.replay(session, [], repository), 'Alice')
surface = PongTestSurface.new
form = Form.new([])
client.attach_view(form, surface)
step = ->(count) { count.times { now += 0.016; client.frame } }
step.call(80)
surface.controls = {'move' => 0, 'hit' => false, 'press' => 1}
step.call(1)
assert(client.engine.ball['dy'] == 1, 'released brief tap was lost')
surface.controls = {'move' => 0, 'hit' => false, 'press' => 0} # recreated field
step.call(1)
client.engine.ball.merge!('x' => 15.0, 'y' => 3.0, 'dy' => -1)
surface.controls['press'] = 1
step.call(1)
assert(client.engine.ball['dy'] == 1, 'first stroke after recreated field was lost')
client.engine.ball.merge!('x' => 15.0, 'y' => 3.0, 'dy' => -1)
step.call(1)
assert(client.engine.ball['dy'] == -1, 'repeated input replayed a tap')
client.detach_view
assert(form.instance_variable_get(:@timers).empty?, 'form timer leaked')
client.attach_view(form, surface)
assert(form.instance_variable_get(:@timers).length == 1, 'duplicate timer on reopen')
events = 2.times.map { |i| {'__id' => i + 1, 'actor' => 'Alice', 'action' => 'pong_point', 'value' => "#{i}:0"} }
client.before_wait(rules.replay(session, events, repository), 'Alice')
step.call(1000)
assert(client.engine.server == 1 && (client.engine.goal || client.engine.ball['dy'] != 0), 'continuous bot did not serve')
client.close

# No first input/snapshot ever arrives: ordinary connected? stays true, but
# the game still diagnoses silence and requests a replacement automatically.
now = 0.0
network = {}
session['__players'] = %w[Alice Bob]
clients = %w[Alice Bob].map do |name|
  c = GameRoomPong::Client.new(Program.new, rules, clock: -> { now }, audio: PongTestAudio.new,
    channel_factory: ->(**args) { PongTestChannel.new(network, **args) })
  c.bind_screen(session_id: 99, table_id: 7, owner: 'Alice', viewer: name, members: -> { %w[Alice Bob] })
  c.start
  c.before_wait(rules.replay(session, [], repository), name)
  c.attach_view(Form.new([]), PongTestSurface.new)
  c
end
network.each_value { |ch| ch.drop = true }
330.times { now += 0.016; clients.each(&:frame) }
assert(network.values.all? { |ch| ch.resets.zero? }, 'handshake reset before native invitation retry')
330.times { now += 0.016; clients.each(&:frame) }
assert(network.values.all? { |ch| ch.resets == 1 }, 'initial silence not repaired or retry storm')
assert(clients.first.engine.tick.zero? && clients.all?(&:paused), 'played before initial handshake')
clients.each(&:close)

# A human guest playing the owner's bot still receives the normal serve
# announcement and can reposition during the break; that is not a sync error.
h = PongHarness.new(players: ['Bob', 'bot:7:1'], viewers: %w[Alice Bob Watcher])
h.advance(220)
guest = h.clients['Bob']
assert(guest.instance_variable_get(:@server_announced), 'remote bot-game player missed serve announcement')
h.accept_point('0:0')
h.advance(10)
assert(guest.paused && guest.instance_variable_get(:@waiting_for_serve), 'ordinary bot-game break presented as outage')
position = h.clients['Alice'].engine.paddles[0]
h.surfaces['Bob'].controls['move'] = 1
h.advance(8)
assert(h.clients['Alice'].engine.paddles[0] > position, 'remote player cannot reposition before serve')
h.surfaces['Bob'].controls['move'] = 0
h.advance(350)
assert(guest.instance_variable_get(:@server_announced), 'next remote serve not announced')
h.close
puts 'PASS Pong integration: LiveSessions scheduler/repository/controller, duplicate/forged result, brief keys/recreated form, bot serving, first-packet watchdog'
