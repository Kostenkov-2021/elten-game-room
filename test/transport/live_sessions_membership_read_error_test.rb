require_relative "../support/native_room_harness"
require_relative "../../lib/game_session_runner"
require_relative "../../games/four_in_a_row"

h = NativeRoomHarness.new(game: GameRoomGames::FourInARow.new, users: %w[Alice Bob])
h.start
transport = h.transports.fetch('Alice')
lobby = LobbyRepository.new(ProgramDouble.new(h.broker.endpoint('Alice')), transport: transport)
view = h.view('Alice')
original = view.method(:participants)
before = h.core.entries.size
[IOError.new('injected membership outage'), NoMethodError.new('injected programming error')].each do |failure|
  view.define_singleton_method(:participants) { raise failure }
  begin
    h.as('Alice') { lobby.snapshot_for(h.table) }
    raise 'unknown membership was published as an empty room'
  rescue failure.class => error
    assert(error.equal?(failure), 'different error masked failed membership read')
  end
  assert(h.core.entries.size == before, 'failed membership read replaced a player or changed the room')
end
view.define_singleton_method(:participants) { original.call }
snapshot = h.as('Alice') { lobby.snapshot_for(h.table) }
assert(snapshot.members.sort == %w[Alice Bob] && snapshot.bots.empty?, 'recovery changed actual membership')
puts 'PASS membership errors stay unknown; no false departures or bot replacements; real membership recovers'
