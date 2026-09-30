require_relative '../support/host_source'
require_relative '../support/native_tasks'
require EltenTestHost.file('src/eapi/server_clock.rb')
require_relative '../../lib/game_room_clock'
require_relative '../../lib/game_session_clock'
require_relative '../../lib/notification_time'
require_relative '../support/server_clock'

def assert(value, message); raise message unless value; end
def unavailable
  yield
  raise 'Unconfirmed clock was accepted'
rescue GameRoomNetworkErrors::ClockUnavailable
end

module Session
  class << self
    attr_accessor :name, :token
    def logged?; !name.nil?; end
  end
end
module EltenLink
  class Client
    def initialize; raise 'Game Room clock attempted HTTP'; end
  end
end

native = EltenAPI::ServerClock
original_tick, original_wall = native.method(:monotonic_time), Time.method(:now)
tick, wall = 10.0, 99_000
native.define_singleton_method(:monotonic_time) { tick }
native.singleton_class.send(:private, :monotonic_time)
Time.define_singleton_method(:now) { Time.at(wall) }
Session.name, Session.token = 'clock-fixture', 'fixture-only-a'
native.instance_variable_set(:@enabled, true)
native.instance_variable_set(:@key, [Session.name, Session.token])
request_class = native.const_get(:Request)
complete = lambda do |stamp, started_at: tick, received_at: tick|
  request = request_class.new([Session.name, Session.token], started_at, nil)
  native.instance_variable_set(:@request, request)
  native.send(:complete, request, stamp, received_at)
end

begin
  assert(GameRoomClock.server_available? && !GameRoomClock.synchronized?, 'Cold host clock was hidden')
  5.times { unavailable { GameRoomClock.synchronize }; unavailable { GameRoomClock.now } }
  complete.call(Time.at(2000))
  assert(GameRoomClock.synchronize == 2000 && GameRoomClock.synchronized?, 'Native sample not adopted')
  [-864_000, 864_000].each do |skew|
    wall = skew
    tick += 10
    1000.times { assert(GameRoomClock.now == 2000 + tick - 10, 'OS clock affected native time') }
  end
  tick = 311
  complete.call(nil)
  assert(GameRoomClock.synchronize == 2301, 'Failed native refresh replaced a confirmed sample')
  threads = 8.times.map { Thread.new { 100.times { GameRoomClock.now } } }
  threads.each(&:value)

  session = {'created_at' => 100, '__server_started_at' => 2000, '__clock_offset' => 5}
  state = GameRoomSessionClock.attach({}, session)
  assert(GameRoomSessionClock.for_state(state) == 396, 'Game epoch changed')
  frozen = GameRoomSessionClock.attach({}, session.merge('__frozen_at' => 2010))
  assert(GameRoomSessionClock.for_state(frozen) == 105, 'Frozen game moved with server clock')
  assert(GameRoomSessionClock.new.now(session) == GameRoomSessionClock.for_state(state), 'UI and action epochs differ')

  old_request = request_class.new([Session.name, Session.token], tick, nil)
  native.instance_variable_set(:@request, old_request)
  Session.token = 'fixture-only-b'
  assert(!GameRoomClock.synchronized?, 'Sample survived account session change')
  unavailable { GameRoomClock.now }
  native.send(:complete, old_request, Time.at(5000), tick)
  unavailable { GameRoomClock.synchronize }
  native.instance_variable_set(:@key, [Session.name, Session.token])
  native.instance_variable_set(:@anchor, nil)
  complete.call(Time.at(3000), started_at: tick - 0.4)
  assert((GameRoomClock.now - 3000.2).abs < 0.0001, 'RTT midpoint was lost in adapter')
  Session.name = nil
  unavailable { GameRoomClock.now }

  [nil, 0, -1, '1000', Float::NAN, Float::INFINITY].each do |bad|
    unavailable { game_room_test_clock { bad }.now }
  end
  broken = game_room_test_clock { raise NoMethodError, 'clock fixture defect' }
  begin
    broken.now
    raise 'Programming error was swallowed'
  rescue NoMethodError
  end
ensure
  native.define_singleton_method(:monotonic_time, original_tick)
  native.singleton_class.send(:private, :monotonic_time)
  Time.define_singleton_method(:now, original_wall)
end

envelope = Struct.new(:date, :expiration, :metadata, keyword_init: true)
app_envelope = Struct.new(:created_at, :metadata, keyword_init: true)
[-7200, 7200].each do |skew|
  metadata = {'created_at' => 1000 + skew, 'expires_at' => 1300 + skew}
  assert(GameRoomNotificationTime.expires_at(envelope.new(date: 1000, expiration: 300, metadata: metadata)) == 1300, 'Sender clock changed expiry')
  opened = app_envelope.new(created_at: 1000, metadata: metadata)
  assert(GameRoomNotificationTime.expires_at(opened) == 1300, 'Opening reset expiry')
  metadata['native_expires_at'] = 1100
  assert(GameRoomNotificationTime.expires_at(opened) == 1100, 'Private deadline extended')
  metadata.delete('native_expires_at')
  metadata['expires_in'] = 50
  assert(GameRoomNotificationTime.expires_at(opened) == 1050, 'Delivery TTL ignored')
end
assert(GameRoomNotificationTime.expires_at(app_envelope.new(created_at: 1000, metadata: {expires_in: 40})) == 1040, 'Symbol metadata lost')
puts 'PASS native ServerClock adapter: no HTTP, cold/outage/recovery, wall jumps, RTT, session invalidation, stale reply, game epoch/freeze and notification TTL'
