require_relative '../support/native_background_capacity'
require_relative '../support/native_room_harness'
require_relative '../../lib/table_watch_runtime'
require_relative '../../lib/tournaments/server_coordination'
require_relative '../../lib/tournaments/local_dispatch_runtime'
include GameRoomTest::Assertions
Capacity = GameRoomTest::NativeBackgroundCapacity

[0, 128].each do |backlog|
  # The participant callback, not a manufactured discovery flag, queues the
  # owner publication. Releasing capacity must publish it without a new wake.
  runtime = TestTaskRuntime.new("discovery-intent-#{backlog}")
  harness = Programs.with_runtime(runtime) { NativeRoomHarness.new(users: ['Alice']) }
  transport = harness.transports.fetch('Alice')
  store = transport.instance_variable_get(:@live_store)
  worker = store.instance_variable_get(:@discovery_work)
  Capacity.until_true do
    transport.maintain_pending_work
    !worker.busy? && store.instance_variable_get(:@discovery_due).empty?
  end
  native = harness.view('Alice')
  assert_equal(1, native.discovery_metadata['player_count'])
  Capacity.with(backlog, runtime: runtime, worker: worker) do |_worker, free_capacity|
    Programs.with_runtime(runtime) { harness.add_client('Bob'); assert(harness.join('Bob')) }
    assert_equal(2, store.send(:table_for, harness.table['__id'])['player_count'])
    transport.maintain_pending_work
    assert_equal(1, native.discovery_metadata['player_count'], 'Discovery bypassed native capacity')
    free_capacity.call
    Capacity.until_true do
      transport.maintain_pending_work
      native.discovery_metadata['player_count'] == 2 && !worker.busy?
    end
    assert(store.instance_variable_get(:@discovery_due).empty?, 'Accepted discovery left a duplicate intention')
  end

  # Read admission and individual notice admission both retain their place.
  [:load, :send].each do |phase|
    Capacity.with(backlog) do |work, free_capacity|
      now, sent, reads = 100.0, [], []
      repository = Object.new
      repository.define_singleton_method(:recipients) { |*_, **_| reads << true; ['Recipient'] }
      sender = GameRoomTableWatch::Sender.new(user: 'Host', repository: repository,
        online: -> { ['Recipient'] }, worker: work, current_user: -> { 'Host' }, clock: -> { now },
        send_notice: ->(recipient, _metadata, _ttl) { sent << recipient })
      table = {'owner' => 'Host', 'status' => 'waiting', 'game' => 'uno', '__id' => 7,
        '__live_session_id' => "notice-#{phase}-#{backlog}"}
      assert(sender.enqueue(table))
      # A completed recipient lookup leaves this exact internal send state;
      # the :load case separately executes the actual lookup through Work.
      sender.instance_variable_get(:@queue).first[:recipients] = [['Recipient', 0]] if phase == :send
      sender.tick
      assert(sent.empty? && reads.empty?, 'A pending notice bypassed the worker limit')
      free_capacity.call
      Capacity.until_true { sender.tick; sent.size == 1 }
      now += 1
      Capacity.until_true { sender.tick; !work.busy? }
      3.times { sender.tick }
      assert_equal(['Recipient'], sent, 'Refused admission dropped or duplicated a recipient')
      assert_equal(phase == :load ? [true] : [], reads)
      sender.close
    end
  end

  [:directory, :wake].each do |kind|
    Capacity.with(backlog) do |work, free_capacity|
      workspace, calls = Object.new, []
      coordinator = GameRoomTournaments::ServerCoordination.new(workspace: workspace,
        user: -> { 'Owner' }, clock: -> { 100 }, worker: work, wake: ->(*) {})
      reference = GameRoomTournaments::ServerCoordination.reference('author' => 'Owner', 'publication_key' => 'a' * 32)
      coordinator.define_singleton_method(:directory) { calls << :directory; {} }
      coordinator.define_singleton_method(:coordinate) { |value, **_| calls << value; {} }
      kind == :directory ? coordinator.bootstrap : coordinator.changed(reference)
      coordinator.tick
      assert(calls.empty?, 'Coordination bypassed native capacity')
      free_capacity.call
      Capacity.until_true { coordinator.tick; calls.length == 1 && !work.busy? }
      3.times { coordinator.tick }
      assert_equal([kind == :directory ? :directory : reference], calls,
        'Admission lost or duplicated a one-shot directory/wake intention')
      coordinator.close
    end
  end

  Capacity.with(backlog) do |unused, free_capacity, runtime|
    dispatcher, calls = Object.new, []
    dispatcher.define_singleton_method(:availability_refresh_due?) { |**_| false }
    dispatcher.define_singleton_method(:advance) { |**_| calls << true; {state: :waiting, reason: :idle} }
    local = GameRoomTournaments::LocalDispatchRuntime.new(dispatcher: dispatcher,
      intent_id: 'intent', identity: 'capacity-test', runtime: runtime)
    local.update
    assert(calls.empty?, 'Local dispatch bypassed native capacity')
    free_capacity.call
    Capacity.until_true { local.update; calls.length == 1 && !local.instance_variable_get(:@work).busy? }
    3.times { local.update }
    assert_equal([true], calls, 'Local dirty intention was lost or duplicated')
    local.close
  end

  [nil, ['uno']].each do |cached_games|
    Capacity.with(backlog) do |_unused, free_capacity, runtime|
      program, reads = Object.new, []
      program.extend(GameRoomTableWatchRuntime)
      receiver = Struct.new(:user, :games).new('Host', cached_games)
      expected_games = cached_games ? ['makao'] : ['uno']
      repository = Object.new
      repository.define_singleton_method(:load) { |user| reads << user; expected_games }
      program.define_singleton_method(:table_watch_receiver) { receiver }
      program.define_singleton_method(:table_watch_repository) { repository }
      Programs.with_runtime(runtime) { program.table_watch_start(refresh: cached_games != nil) }
      assert(reads.empty?, 'Cold preference read bypassed native capacity')
      assert_equal({state: :loading, games: nil}, program.table_watch_preferences_snapshot,
        'An unadmitted explicit refresh exposed old preferences as a fresh result')
      if backlog == 128
        assert(program.instance_variable_get(:@table_watch_loader).nil?, 'Refused cold load retained an idle worker')
      end
      free_capacity.call
      Capacity.until_true do
        Programs.with_runtime(runtime) { program.table_watch_start }
        program.table_watch_preferences_snapshot[:state] == :ready
      end
      assert_equal(['Host'], reads, 'Cold preference load was lost or duplicated')
      assert_equal(expected_games, receiver.games)
    ensure
      program&.table_watch_stop
    end
  end
end

closed = Object.new
closed.define_singleton_method(:start) { false }
assert(!GameRoomBackground.admit(closed) { raise 'Declined work ran' })
failure = RuntimeError.new('Not a capacity error')
invalid = Object.new
invalid.define_singleton_method(:start) { raise failure }
assert(assert_raises(RuntimeError) { GameRoomBackground.admit(invalid) {} }.equal?(failure),
  'Admission swallowed an internal programming failure')
puts 'PASS native admission for discovery, notice load/send, server startup/wake, local dirty dispatch and cold preferences; no hidden retries or changed FIFO'
