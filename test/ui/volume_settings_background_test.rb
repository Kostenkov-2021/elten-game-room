require_relative '../support/volume_and_help'

state = { 'sound_volumes' => { 'all' => 100, 'game' => 100 }, 'invitation_notifications' => 'contacts',
  'widget_contacts_only' => true, 'pong' => { 'auto_return' => false } }
original = Marshal.load(Marshal.dump(state))
io_lock, writes = Mutex.new, []
entered, release = Queue.new, Queue.new
blocked, fail_write = true, false
published = nil
writer = nil
writer = GameRoomVolumeSettings.new(values: GameRoomPreferences.normalize(state, []),
  publish: ->(values) { published = Marshal.load(Marshal.dump(values)); writer.remember(published) },
  write: ->(patch, &edit) {
    io_lock.synchronize do
      if blocked
        entered << true
        release.pop
        blocked = false
      end
      raise IOError, 'test disk unavailable' if fail_write
      changed = Marshal.load(Marshal.dump(state))
      changed['sound_volumes'] = GameRoomPreferences.sound_volumes(changed).merge(patch)
      edit.call(changed)
      writes << patch.dup
      state.replace(changed)
      Marshal.load(Marshal.dump(state))
    end
  })

def await_writer(writer)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
  while writer.instance_variable_get(:@thread)&.alive?
    raise 'writer timeout' if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    sleep 0.001
  end
end

begin
  writer.set('all', 90)
  entered.pop
  before = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  80.times { |i| writer.set('game', i % 60) }
  writer.set('all', 40)
  assert(Process.clock_gettime(Process::CLOCK_MONOTONIC) - before < 0.08, 'hotkeys waited on I/O')
  assert(writer.snapshot['sound_volumes']['all'] == 40 && state == original, 'optimistic update changed disk/privacy')
  release << true
  await_writer(writer)
  assert(writes.length == 2, 'rapid keys were not coalesced')
  assert(state['sound_volumes']['all'] == 40 && state['sound_volumes']['game'] == 19, 'last values were lost')
  assert(state.reject { |k, _v| k == 'sound_volumes' } == original.reject { |k, _v| k == 'sound_volumes' }, 'unrelated preferences overwritten')

  # Opening/reloading Settings while a write is queued must still show the
  # current audible value, not resurrect the older file's volume.
  writer.set('chat', 20)
  writer.remember(GameRoomPreferences.normalize(state, []))
  assert(writer.snapshot['sound_volumes']['chat'] == 20, 'reload erased queued hotkey')
  writer.update { |data| data['pong']['auto_return'] = true }
  await_writer(writer)
  assert(state['sound_volumes']['chat'] == 20 && state['pong']['auto_return'], 'unrelated explicit save lost hotkey')
  writer.set('game', 5)
  writer.update { |data| data['sound_volumes']['game'] = 55 }
  await_writer(writer)
  assert(state['sound_volumes']['game'] == 55 && writer.snapshot['sound_volumes']['game'] == 55, 'older hotkey overwrote explicit Save')

  fail_write = true
  writer.set('all', 10)
  await_writer(writer)
  assert(writer.snapshot['sound_volumes']['all'] == 10 && state['sound_volumes']['all'] == 40, 'failed save changed confirmed disk')
  assert(writer.take_error.is_a?(IOError) && writer.take_error.nil?, 'failure not delivered once')
  fail_write = false
  writer.set('all', 30)
  writer.close
  assert(state['sound_volumes']['all'] == 30, 'unload lost last pending value')
  assert(!writer.set('all', 0), 'closed writer accepted a late key')
ensure
  release << true
  writer.close
end
puts 'PASS background volume: slow/failed storage, immediate mix, bounded coalescing, save/reload ordering and final flush'
