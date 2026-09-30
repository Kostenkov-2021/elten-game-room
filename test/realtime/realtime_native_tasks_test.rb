require_relative "../support/host_source"
require_relative "../support/pong_client"

# Run against the host's actual Tasks implementation, without starting ELTEN
# or contacting a service. Other checkouts can supply their host source path.
source = ARGV[0] || EltenTestHost.file("src/eapi/tasks.rb")
raise "Missing required native Tasks source: #{source}" unless File.file?(source)
module EltenAPI; end unless defined?(EltenAPI)
require source
Object.include(EltenAPI)

owner, gate, frames = Thread.current, Queue.new, 0
EltenAPI.define_method(:loop_update) do
  assert(Thread.current == owner, 'native UI ran in a network worker')
  frames += 1
  gate << true
  Thread.pass
end

client = Object.new
updates, closes = 0, 0
client.define_singleton_method(:network_task_ui) do |**options|
  ui = GameRoomRealtime::TaskUI.new(**options, clock: -> { 0.0 }, tick: -> {
    assert(Thread.current == owner, 'Pong was ticked outside the UI thread')
    updates += 1
  })
  ui.define_singleton_method(:close) { closes += 1; super() }
  ui
end
screen = GameScreen.allocate
screen.instance_variable_set(:@game_client, client)
result = screen.send(:network_task, 'Saving', ui: :none) do
  assert(Thread.current != owner, 'server operation blocked the UI owner')
  40.times { gate.pop }
  :saved
end
assert(result == :saved && updates >= 1 && closes == 1, 'real Tasks.run did not maintain the optional client')
previous = updates
screen.instance_variable_set(:@game_client, nil)
result = screen.send(:network_task, 'Other game', ui: :none) { :normal }
assert(result == :normal && updates == previous, 'ordinary games entered the real-time hook')
screen.instance_variable_set(:@game_client, client)
begin
  screen.send(:network_task, 'Failed write', ui: :none) { raise 'intentional failure' }
  raise 'write error was swallowed'
rescue RuntimeError => error
  raise unless error.message == 'intentional failure'
end
assert(closes == 2, 'failed write leaked its task UI')
puts 'PASS actual ELTEN Tasks.run contract: owner-thread client updates, worker-thread I/O, other games unchanged, ensure cleanup'
