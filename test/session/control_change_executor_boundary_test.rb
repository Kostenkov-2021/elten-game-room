require 'timeout'
require_relative "../support/scientific_war_control"

f = ScientificWarControlFixture.new
context = f.context('Alice')
context.random_source = GameRoomRandom::SeededSource.new(91)
runner = f.as('Alice') do
  GameRoomSessionRunner.new(program: f.app, transport: f.app.transport, repository: f.app.games,
    game: f.game, session: f.session, table: f.table, owner: 'Alice', viewer: 'Alice',
    room_snapshot_provider: -> { f.app.lobby.snapshot_for(f.table) }, context: context, covered: -> { true })
end
runner.send(:register_execution_group)
worker = nil
begin
  # The same boundary is reentrant when management originates from executor
  # work; a different table's management is independent of this lock.
  Timeout.timeout(3) do
    runner.synchronize do
      assert(GameRoomSessionRunner.synchronize_table(program: f.app, table_id: f.table['__id'], viewer: 'Alice') { true }, 'Boundary is not reentrant')
      unrelated = Thread.new do
        GameRoomSessionRunner.synchronize_table(program: f.app, table_id: f.table['__id'] + 1, viewer: 'Alice') { :independent }
      end
      assert(unrelated.value == :independent, 'Unrelated table was serialized')
    end
  end

  attempted, completed = Queue.new, Queue.new
  transfer = f.native.method(:transfer_ownership)
  calls = 0
  f.native.define_singleton_method(:transfer_ownership) do |target|
    calls += 1
    worker = Thread.new do
      f.as('Alice') do
        attempted << true
        begin
          runner.synchronize { f.choose('Alice', f.bot) }
          completed << :committed
        rescue GameRoomNetworkErrors::GamePaused, ArgumentError
          completed << :rejected
        end
      end
    end
    Timeout.timeout(3) { attempted.pop }
    assert(completed.empty?, 'Old-owner executor passed the management boundary')
    transfer.call(target)
    raise EltenAPI::LiveSessions::TimeoutError, 'lost reply after confirmed transfer'
  end
  f.as('Alice') do
    assert(f.app.send(:change_table_control, f.table, :transfer_master, 'Bob'), 'Confirmed lost-reply transfer was rejected')
  end
  Timeout.timeout(3) { worker.join }
  assert(completed.pop == :rejected, 'Old owner sealed a bot secret after ownership transfer')
  assert(calls == 1 && !f.native.owner?, 'Uncertain transfer was retried or rolled back')
  f.snapshot('Bob')
  assert(f.replay('Bob').state[:commits].empty?, 'An inaccessible old-owner commitment reached the stack')
ensure
  worker&.join(3)
  runner.close
  runner.send(:unregister_execution_group)
end

# Starting a new screen while a management operation is already in progress
# must reuse its boundary even when no executor existed at operation start.
key = [f.app.class, f.table['__id'], 'alice']
registered, entered = Queue.new, Queue.new
begin
  GameRoomSessionRunner.synchronize_table(program: f.app, table_id: f.table['__id'], viewer: 'Alice') do
    worker = Thread.new do
      runner.send(:register_execution_group)
      registered << true
      runner.synchronize { entered << true }
    end
    Timeout.timeout(3) { registered.pop }
    assert(entered.empty?, 'New executor bypassed an in-flight management boundary')
    runner.send(:unregister_execution_group)
    assert(GameRoomSessionRunner::GROUPS.key?(key), 'Last executor retirement removed a still-held management boundary')
  end
  Timeout.timeout(3) { worker.join }
  assert(entered.pop, 'New executor never resumed after management')
  assert(!GameRoomSessionRunner::GROUPS.key?(key), 'Temporary management boundary was leaked')
ensure
  worker&.join(3)
end

puts 'Control executor boundary: reentrant, table-local, prevents bot sealing during transfer, lost reply remains idempotent OK'
