require 'thread'
require 'timeout'

module EltenLink
  class Error < StandardError
    attr_reader :code
    def initialize(code)
      @code = code
      super(code)
    end
  end

  module Apps
    class << self
      attr_accessor :factory
      def table(_client, _uuid, name)
        factory.call(name)
      end
    end
  end
end

require_relative "../../lib/game_room_server_tables"

def assert(value, message)
  raise message unless value
end

def finish(thread)
  Timeout.timeout(3) { thread.value }
end

def provider
  EltenLink::Apps.factory = ->(_name) { Object.new }
  GameRoomServerTables.new(Struct.new(:server_app_uuid).new('local-test'), client: Object.new)
end

# Keep a real provider request pending while two local operations complete.
tables = provider
tables.instance_variable_set(:@access_state, :available)
entered, release = Queue.new, Queue.new
network = Thread.new { tables.perform { entered << true; release.pop; :saved } }
read = reset = nil
begin
  Timeout.timeout(3) { entered.pop }
  read = Thread.new { tables.fetch('users') }
  reset = Thread.new { tables.reset_access! }
  read.join(0.25)
  reset.join(0.25)
  read_free, reset_free = !read.alive?, !reset.alive?
ensure
  release << true
  [network, read, reset].compact.each { |thread| finish(thread) }
end
assert(read_free, 'local table lookup waited for a network response')
assert(reset_free, 'access reset waited for a network response')
assert(tables.access_state == :unchecked, 'the old request restored access after reset')

# A queued operation belongs to the access generation in which it started.
tables = provider
tables.instance_variable_set(:@access_state, :available)
entered, release = Queue.new, Queue.new
first = Thread.new { tables.perform { entered << true; release.pop } }
second = nil
calls = []
begin
  Timeout.timeout(3) { entered.pop }
  second = Thread.new { tables.perform(default: :skipped) { calls << :unwanted; :written } }
  Timeout.timeout(3) { Thread.pass until second.status == 'sleep' }
  tables.reset_access!
ensure
  release << true
  finish(first)
end
assert(finish(second) == :skipped && calls.empty?, 'a queued old-generation write was sent')

# An old denial must still reach its caller, but cannot revoke a new context.
tables = provider
tables.instance_variable_set(:@access_state, :available)
entered, release = Queue.new, Queue.new
failure = EltenLink::Error.new('apps.tables.stamp_required')
request = Thread.new do
  begin
    tables.perform { entered << true; release.pop; raise failure }
  rescue EltenLink::Error => error
    error
  end
end
begin
  Timeout.timeout(3) { entered.pop }
  tables.reset_access!
ensure
  release << true
end
assert(finish(request).equal?(failure), 'the original write denial was hidden')
assert(tables.access_state == :unchecked && tables.last_error.nil?, 'a stale denial overwrote the reset')

# A successful probe that finishes after reset does not enable the new context.
tables = provider
entered, release = Queue.new, Queue.new
raw = Object.new
raw.define_singleton_method(:select) do |**options|
  assert(options == {where: {'username' => 'Alice'}, limit: 1}, 'probe options changed')
  entered << true
  release.pop
  []
end
EltenLink::Apps.factory = ->(_name) { raw }
probe = Thread.new { tables.check_access(username: 'Alice') }
begin
  Timeout.timeout(3) { entered.pop }
  tables.reset_access!
ensure
  release << true
end
assert(finish(probe) == false, 'a stale probe was reported as current access')
assert(!tables.available? && tables.last_error.nil?, 'a stale probe enabled the new context')

# Network work remains serial even though local reads are no longer blocked.
tables = provider
tables.instance_variable_set(:@access_state, :available)
guard = Mutex.new
active = maximum = 0
threads = 6.times.map do
  Thread.new do
    tables.perform do
      guard.synchronize { active += 1; maximum = [maximum, active].max }
      sleep(0.005)
      guard.synchronize { active -= 1 }
    end
  end
end
threads.each { |thread| finish(thread) }
assert(maximum == 1, 'table requests lost their serial execution')
puts 'Server table concurrency tests passed (5 cases)'
