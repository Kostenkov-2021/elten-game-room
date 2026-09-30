require_relative "../../support/tysiac_two_player"
require_relative "../../support/native_room_harness"

fixture = TwoPlayerTysiacFixture.new
fixture.auction
fixture.choose
3.times { fixture.discard }
fixture.move({'kind'=>'command', 'action'=>'contract', 'bid'=>100})
h = NativeRoomHarness.new(game: fixture.game, users: fixture.players,
  options: JSON.parse(fixture.session.fetch('options')))
h.start
fixture.events.each do |event|
  h.write(event.fetch('actor'), [GameRoomGames::EventCommand.new(action: event.fetch('action'), value: event.fetch('value'))])
end
before = h.replay('Alice')
assert(before.state[:phase] == :playing, 'Legal prefix did not reach play')
['normal|XX', 'normal', 'normal|', '|', '', 'invalid|AS', 'normal|AS|extra'].each do |value|
  h.write(before.current_player, [GameRoomGames::EventCommand.new(action: 'play', value: value)])
  h.users.each do |user|
    replay = h.replay(user)
    assert(replay.state == before.state && replay.accepted_events == before.accepted_events, "Malformed command changed state: #{value}")
  end
end
action = h.game.legal_actions(before, before.current_player).first
h.submit(before.current_player, action)
h.assert_converged('Next legal move after malformed history')
assert(h.replay('Alice').accepted_events.length == before.accepted_events.length + 1, 'Malformed entries blocked subsequent legal play')
puts 'PASS Tysiac: malformed participant records ignored without mutation; two clients converge on next legal move'
