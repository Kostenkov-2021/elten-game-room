require_relative '../support/tournament_forfeit_native'

parent = File.expand_path('../tournaments/forfeit_start_fence_native_test.rb', __dir__)
original_thread = Thread.method(:new)
original_close = TournamentForfeitNative::Fixture.instance_method(:close)
worker, observations, caught = nil, nil, nil
joins, started, release = [], Queue.new, Queue.new
begin
  Thread.define_singleton_method(:new) do |*values, **options, &block|
    location = caller_locations(1, 1).first
    unless location.path == parent && location.base_label == 'other_worker'
      next original_thread.call(*values, **options, &block)
    end
    worker = original_thread.call(*values, **options) do |*arguments|
      started << true
      release.pop
      block.call(*arguments)
    end
    native_join = worker.method(:join)
    worker.define_singleton_method(:join) do |*arguments|
      joins << arguments
      # Exercise the actual parent's timeout without adding ten seconds to
      # every suite run. Its real owned thread is still blocked at this point.
      if arguments == [10]
        started.pop
        nil
      else
        native_join.call(*arguments)
      end
    end
    worker
  end
  TournamentForfeitNative::Fixture.define_method(:close) do
    observations = {alive: worker&.alive?, joins: joins.map(&:dup), primary: $!}
    original_close.bind_call(self)
  end
  begin
    namespace = Module.new
    namespace.extend(namespace)
    namespace.module_eval(File.read(parent, encoding: 'UTF-8'), parent, 1)
  rescue StandardError => error
    caught = error
  end
ensure
  Thread.define_singleton_method(:new, original_thread)
  TournamentForfeitNative::Fixture.define_method(:close, original_close)
  # Original-source negative controls must not leak this regression's thread.
  # Inspect maintained cleanup above, before this independent safety net.
  worker&.kill if worker&.alive?
  worker&.join(5)
end
assert(caught&.message == 'Independent entry worker did not finish', 'Actual parent did not reach its timeout assertion')
assert(observations && observations[:primary].equal?(caught), 'Worker cleanup replaced the original failure')
assert(observations[:alive] == false, 'Actual parent closed its fixture with an entry worker still alive')
assert_equal([[10], [5]], observations[:joins], 'Owned entry worker cleanup did not use a bounded join')
puts 'PASS actual forfeit-entry parent: timed-out owned thread ends before fixture teardown, original assertion preserved'
