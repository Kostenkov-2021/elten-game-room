require_relative 'host_source'
require EltenTestHost.file('src/eapi/resources.rb')
require EltenTestHost.file('src/eapi/tasks.rb')

# Headless tests do not load Programs' package/native loader. Keep the real
# Tasks implementation and provide only its absent runtime lookup boundary.
module Programs
  class Runtime; end unless const_defined?(:Runtime)
  def self.current_runtime; Thread.current[:game_room_test_runtime]; end unless respond_to?(:current_runtime)
  def self.runtime_from_caller; nil; end unless respond_to?(:runtime_from_caller)
  def self.runtime_for(_owner); nil; end unless respond_to?(:runtime_for)
  def self.runtime_registered?(runtime); !runtime.managed_resources.closed?; end unless respond_to?(:runtime_registered?)
  unless respond_to?(:with_runtime)
    def self.with_runtime(runtime)
      previous = Thread.current[:game_room_test_runtime]
      Thread.current[:game_room_test_runtime] = runtime
      yield
    ensure
      Thread.current[:game_room_test_runtime] = previous
    end
  end
end

class TestTaskRuntime < Programs::Runtime
  attr_reader :manifest, :managed_resources

  def initialize(id = 'game-room-test')
    @manifest = Struct.new(:id).new(id)
    @managed_resources = EltenAPI::Resources::Registry.new
  end

  def manage(resource); @managed_resources.manage(resource); end
  def release(resource); @managed_resources.release(resource); end
  def close; @managed_resources.close; end
end

# Test-only wait: don't make application code expose or retain native threads.
require 'timeout'
def wait_background_work(work, timeout: 3)
  Timeout.timeout(timeout) do
    loop do
      work.busy? # Also admits queued work when native capacity becomes free.
      handle = work.instance_variable_get(:@handle)
      if work.closed?
        # Closing discards an outcome, not the native worker. In these isolated
        # fixtures wait for the scope's actual workers before asserting effects.
        native = EltenAPI::Tasks::Handle
        workers = native.const_get(:MUTEX).synchronize do
          native.const_get(:WORKERS).select { |scope, _| scope == work.scope }.map(&:last)
        end
        workers.each(&:join)
        break
      end
      break if handle&.done? || work.instance_variable_get(:@result)
      Thread.pass
    end
  end
  true
end
