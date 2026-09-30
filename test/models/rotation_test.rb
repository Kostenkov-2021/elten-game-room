require_relative "../../lib/axel_pong/rotation"

def assert(value, message); raise message unless value; end

assert(defined?(GameRoomPong::Rotation), 'Pong has no service rotation model')
[0, 1].each do |first|
  16.times do |rally|
    rotation = GameRoomPong::Rotation.new(rally: rally, first_server: first)
    server = (first + rally / 2) % 2
    assert(rotation.teams == [0, 1] && !rotation.doubles?, 'singles team layout changed')
    assert(rotation.server == server && rotation.receiver == 1 - server, 'singles service block changed')
    assert(rotation.members(0) == [0] && rotation.members(1) == [1], 'singles members changed')
    8.times do |turn|
      assert(rotation.hitter(turn) == (server + turn) % 2, 'singles hitter order changed')
      assert(rotation.team(turn % 2) == turn % 2, 'singles court side changed')
    end
  end
end

pairs = [[0, 2], [3, 1], [1, 3], [2, 0], [0, 3], [2, 1], [1, 2], [3, 0]]
[[0, 0, 1, 1], [0, 1, 0, 1], [1, 0, 1, 0]].each do |teams|
  [0, 1].each do |first|
    members = [first, 1 - first].map { |team| teams.each_index.select { |seat| teams[seat] == team } }
    seats = members.flatten
    48.times do |rally|
      rotation = GameRoomPong::Rotation.new(teams: teams, rally: rally, first_server: first)
      server, receiver = pairs[(rally / 2) % pairs.length].map { |seat| seats[seat] }
      assert(rotation.doubles? && rotation.teams == teams, 'doubles team layout lost')
      assert([rotation.server, rotation.receiver] == [server, receiver], 'doubles service pairing changed')
      assert(rotation.members(first) == members[0], 'seat order within the starting team changed')
      ring = [server, receiver,
        seats.find { |seat| teams[seat] == teams[server] && seat != server },
        seats.find { |seat| teams[seat] == teams[receiver] && seat != receiver }]
      12.times do |turn|
        assert(rotation.hitter(turn) == ring[turn % 4], 'doubles hitter ring skipped a partner')
        assert(rotation.team(rotation.hitter(turn)) == teams[ring[turn % 4]], 'participant was used as court side')
      end
    end
  end
end

invalid_teams = [nil, '0011', [], [0], [1, 0], [0, 0], [0, 1, 1], [0, 0, 0, 1],
  [0, 1, 1, 2], [0.0, 1.0], [0, 0, 1, 1.0], [false, false, true, true], [0, 0, 1, 1, 0, 1]]
invalid_teams.each do |teams|
  begin
    GameRoomPong::Rotation.new(teams: teams)
  rescue ArgumentError
    next
  end
  raise "invalid teams accepted: #{teams.inspect}"
end
source = [0, 0, 1, 1]
rotation = GameRoomPong::Rotation.new(teams: source)
source[0] = 1
assert(rotation.teams == [0, 0, 1, 1] && rotation.teams.frozen?, 'caller can mutate the match teams')

puts 'PASS Pong rotation: singles and doubles service cycles, both first teams, arbitrary seats, hitter rings, strict teams'
