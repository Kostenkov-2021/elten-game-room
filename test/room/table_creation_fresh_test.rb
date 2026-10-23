require_relative '../support/native_live_sessions'

# Explicit create is not a request to reopen another accepted visit. The
# programme-window guard and tournament's per-match journal are separate.
[false, true].product([false, true]).each do |private_table, fresh_endpoint|
  broker = NativeLiveSessionsBroker.new
  transports = []
  make = lambda do |endpoint|
    program = ProgramDouble.new(endpoint)
    transport = GameRoomTransport.new(program)
    transports << transport
    LobbyRepository.new(program, transport: transport)
  end
  first_endpoint = broker.endpoint('Alice')
  first_lobby = make.call(first_endpoint)
  first = first_lobby.create_table(name: 'Original table', game: 'tic_tac_toe', owner: 'Alice', private_table: private_table)
  original = broker.cores.fetch(first.table.fetch('__live_session_id'))
  before = JSON.generate([original.metadata, original.entries])
  next_endpoint = fresh_endpoint ? broker.endpoint('Alice', fresh: true) : first_endpoint
  next_endpoint.define_singleton_method(:discover_sessions) { |**_| raise 'Explicit creation searched for another table' }
  lobby = fresh_endpoint ? make.call(next_endpoint) : first_lobby
  second = lobby.create_table(name: 'Requested new table', game: 'uno', owner: 'Alice', private_table: private_table)
  assert(second.created? && first.table['__id'] != second.table['__id'], 'Explicit creation returned an earlier table')
  assert_equal('uno', second.table['game'])
  assert_equal('Requested new table', second.table['name'])
  assert_equal(private_table, second.table['private'])
  assert_equal(2, broker.cores.size, 'The explicit second create did not reach the native creator')
  assert_equal(before, JSON.generate([original.metadata, original.entries]), 'Creating another table changed the original')
ensure
  broker&.cores&.each_value { |core| core.views.find { |view| !view.closed? && view.owner? }&.close }
  transports&.each { |transport| transport.instance_variable_get(:@live_store).instance_variable_get(:@discovery_work).close }
end
puts 'PASS explicit fresh creation: same/new connection, public/private, no catalogue lookup, redirect or changes to the original table'
