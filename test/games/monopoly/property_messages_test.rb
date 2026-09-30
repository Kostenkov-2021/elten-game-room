require_relative "../../support/new_games_fixture"

game = GameRoomGames::Monopoly.new
repository = NewGames116Repository.new(%w[Alice Bob])
fresh_state = lambda do
  state = game.send(:initial_state, %w[Alice Bob], game.default_options)
  state[:owners].merge!(1 => "Alice", 3 => "Alice", 5 => "Alice")
  state[:cash]["Alice"] = 5000
  state
end
check = lambda do |state, action, index, expected|
  event = { "id" => 1, "action" => action, "value" => index.to_s, "actor" => "Alice" }
  history = []
  assert(game.send(:apply_property_action, state, event, "Alice", repository, history), "Rejected #{action}")
  assert(history.one? && history.first.text == expected, "Unexpected #{action} message: #{history.map(&:text).inspect}")
  replay = GameRoomGames::Replay.new(state: state, history: history)
  %w[Alice Bob Observer].each do |viewer|
    assert(game.describe_event(event, repository, replay, viewer) == [expected], "Spoken #{action} differs from history")
  end
end

state = fresh_state.call
name = state[:board][1][:name]
label = game.send(:action_label, { "action" => "build", "property" => 1 }, state, "Alice")
assert(label.include?("cost: 50") && label.include?("buildings:"), "Building menu lost details")
check.call(state, "build", 1, "Alice builds the first house on #{name}.")
assert(state[:houses][1] == 1 && state[:cash]["Alice"] == 4950, "Building economics changed")
check.call(state, "sell", 1, "Alice sells a house on #{name}.")
assert(state[:houses][1] == 0 && state[:cash]["Alice"] == 4975, "Selling economics changed")

%w[second third fourth].each_with_index do |ordinal, index|
  state = fresh_state.call
  state[:houses].merge!(1 => index + 1, 3 => index + 1)
  check.call(state, "build", 1, "Alice builds the #{ordinal} house on #{name}.")
  assert(state[:houses][1] == index + 2 && state[:cash]["Alice"] == 4950, "Numbered building changed the operation")
end

state = fresh_state.call
state[:houses].merge!(1 => 4, 3 => 4)
check.call(state, "build", 1, "Alice builds a hotel on #{name}.")
check.call(state, "sell", 1, "Alice sells a hotel on #{name}.")
assert(state[:houses][1] == 4, "Hotel sale lost remaining houses")

state = fresh_state.call
station = state[:board][5][:name]
label = game.send(:action_label, { "action" => "mortgage", "property" => 5 }, state, "Alice")
assert(label.include?("receive 100"), "Mortgage menu lost proceeds")
check.call(state, "mortgage", 5, "Alice mortgages #{station}.")
label = game.send(:action_label, { "action" => "unmortgage", "property" => 5 }, state, "Alice")
assert(label.include?("cost: 110"), "Redemption menu lost cost")
check.call(state, "unmortgage", 5, "Alice unmortgages #{station}.")
assert(state[:cash]["Alice"] == 4990 && !state[:mortgaged][5], "Mortgage economics changed")

state = fresh_state.call
state[:houses].merge!(1 => 5, 3 => 5)
state[:board].select { |square| square[:type] == :property && ![1, 3].include?(square[:index]) }.first(8).each do |square|
  state[:houses][square[:index]] = 4
end
group = game.send(:property_group_label, state[:board][1])
check.call(state, "sell", 1, "Alice sells all buildings in the #{group}.")
assert(state[:houses].values_at(1, 3) == [0, 0], "Group liquidation changed")
history = []
assert(!game.send(:apply_property_action, state, { "id" => 2, "action" => "sell", "value" => "1" }, "Alice", repository, history), "Empty property sold")
assert(history.empty?, "Failed operation announced as successful")

puts "Monopoly: concise shared/spoken property messages; unchanged menu details and economics passed"
