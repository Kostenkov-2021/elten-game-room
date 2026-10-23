require_relative '../support/assertions'
include GameRoomTest::Assertions

fixture = File.expand_path('../support/host_session.rb', __dir__)
previous = Object.const_get(:Session) if Object.const_defined?(:Session, false)
native = nil
begin
  Object.send(:remove_const, :Session) if previous
  require fixture
  native = EltenAPI::Structs::Session
  previous_name = native.name
  assert(Session.equal?(native), 'Not the native account module')
  assert(Session.name.nil?, 'Fixture invented a signed-in account')
  Session.name = 'Native account'
  require fixture
  assert(Session.name == 'Native account', 'Repeated fixture reset the account')

  Object.send(:remove_const, :Session)
  scenario = Module.new
  scenario.define_singleton_method(:name) { 'Scenario identity' }
  Object.const_set(:Session, scenario)
  load fixture
  assert(Session.equal?(scenario), 'Scenario account module replaced')
  assert(Session.name == 'Scenario identity', 'Scenario account changed')
  assert(native.equal?(EltenAPI::Structs::Session), 'Native account module replaced')
ensure
  native.name = previous_name if native
  Object.send(:remove_const, :Session) if Object.const_defined?(:Session, false)
  Object.const_set(:Session, previous) if previous
end

puts 'PASS shared native Session fixture: real host identity, no invented user, repeat load and explicit scenario preserved'
