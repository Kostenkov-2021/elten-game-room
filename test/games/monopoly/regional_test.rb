require_relative "../../support/new_games_fixture"

game = GameRoomGames::Monopoly.new
players = %w[Alice Bob Carol]
repository = NewGames116Repository.new(players)
new_state = ->(id) { game.send(:initial_state, players, game.normalize_options("board" => id)) }
view = ->(state) { GameRoomGames::Replay.new(players: players, board: state[:board], state: state,
  current_player: state[:current_player], history: [], accepted_events: [], winner: nil) }
event = ->(action, value = "") { { "id" => 7, "actor" => "Alice", "action" => action, "value" => value } }

# Independent observations from the QC UI, not derived from production profiles.
expected = {
  "atlantic_city" => [40, 1500, 60, "Mediterranean avenue", "Boardwalk"],
  "london" => [40, 1500, 60, "Old Kent Road", "Mayfair"],
  "europe" => [40, 15_000_000, 600_000, "Vilnius", "Paris"],
  "roma" => [40, 1500, 60, "Vicolo del moro", "Parco del Pincio"],
  "latin_america" => [60, 9750, 180, "Montevideo", "Río de Janeiro"],
  "barcelona" => [40, 15_000_000, 600_000, "Calle de Lauria", "Paseo de Gracia"],
  "turkey" => [40, 1500, 60, "Ardahan", "istanbul"],
  "slovakia" => [40, 1500, 60, "Stakčín", "Bratislava"],
  "serbia" => [40, 15_000_000, 600_000, "Jagodina", "Beograd"],
  "czechia" => [40, 37_500, 1500, "Děčín", "Praha"],
  "russia" => [40, 1500, 60, "Пенза", "Батайск"],
  "ukraine" => [40, 1500, 60, "Мелітополь", "Київ"],
  "romania" => [60, 35_000_000, 600_000, "Vaslui", "București"],
  "balkans" => [60, 7000, 120, "Durrës", "Istanbul"],
  "indonesia" => [60, 35_000_000, 600_000, "Manokwari", "Jakarta"],
  "southeast_asia" => [60, 7000, 120, "Nay Pyi Taw", "Singapore"],
  "india" => [40, 1500, 60, "Shimla", "Mumbai"],
  "twelve_nations" => [60, 7000, 120, "Linz", "New york"]
}
expected.each do |id, (size, cash, price, first, last)|
  state = new_state.call(id)
  board = state[:board]
  data = state[:board_data]
  factor = price / 60
  assert([board.size, state[:cash]["Alice"], board[1][:price], board[1][:name], board.last[:name]] ==
    [size, cash, price, first, last], "#{id}: observed regional data differs")
  assert(board.map { |square| square[:index] } == (0...size).to_a, "#{id}: unstable indices")
  assert(board.none? { |square| square[:name].match?(/White duck|papierek|\AClose\z/) }, "#{id}: copied UI ownership into content")
  groups = board.select { |square| square[:type] == :property }.group_by { |square| square[:group] }
  assert(groups.size == (size == 60 ? 12 : 8), "#{id}: missing colour groups")
  assert(groups.values.all? { |squares| [2, 3].include?(squares.size) }, "#{id}: invalid colour set")
  assert(board.count { |square| square[:type] == :jail } == 1 && board.count { |square| square[:type] == :go_to_jail } == 1,
    "#{id}: invalid jail layout")
  assert([data[:bank_houses], data[:bank_hotels]] == (size == 60 ? [48, 18] : [32, 12]), "#{id}: wrong bank stock")

  board.select { |square| square[:type] == :railroad }.each_with_index do |square, count|
    state[:owners][square[:index]] = "Bob"
    assert(game.send(:rent_for, state, square, "Bob") == [25, 50, 100, 200, 400, 600][count] * factor,
      "#{id}: wrong rent with #{count + 1} stations")
  end
  state[:last_roll] = 7
  board.select { |square| square[:type] == :utility }.each_with_index do |square, count|
    state[:owners][square[:index]] = "Bob"
    assert(game.send(:rent_for, state, square, "Bob") == [4, 10, 25, 50][count] * 7 * factor,
      "#{id}: wrong rent with #{count + 1} utilities")
  end
  state[:owners].clear
  state[:positions]["Alice"] = size - 1
  game.send(:move_player, state, "Alice", 2, 1, [])
  assert(state[:positions]["Alice"] == 1 && state[:cash]["Alice"] == cash + data[:salary], "#{id}: wrong lap or salary")
  state[:positions]["Alice"] = size - 1
  game.send(:move_player, state, "Alice", 1, 2, [])
  assert(state[:cash]["Alice"] == cash + 3 * data[:salary], "#{id}: exact Start does not double salary")
  state[:positions]["Alice"] = board.find { |square| square[:type] == :go_to_jail }[:index]
  game.send(:resolve_square, state, "Alice", 3, [])
  expected_jail = id == "indonesia" ? 50 : 10
  assert(state[:positions]["Alice"] == expected_jail && state[:jail]["Alice"] == 3, "#{id}: jail is at the wrong end of the board")
  state[:phase] = :awaiting_roll
  jail_fee = (data[:salary] + 2) / 4
  state[:cash]["Alice"] = jail_fee - 1
  assert(game.legal_actions(view.call(state), "Alice").none? { |a| a["action"] == "pay_jail" }, "#{id}: unscaled jail eligibility")
  assert(!game.send(:apply_jail_action, state, event.call("pay_jail"), "Alice", repository, []), "#{id}: jail fee bypassed")
  state[:cash]["Alice"] = jail_fee
  assert(game.send(:apply_jail_action, state, event.call("pay_jail"), "Alice", repository, []) && state[:cash]["Alice"] == 0,
    "#{id}: wrong jail fee")
  assert(game.send(:auction_increment, state) == 10 * factor, "#{id}: unscaled auction increment")

  [:chance, :community].each do |deck|
    cards = game.send(:card_definitions, state, deck)
    base = game.send(:card_definitions, new_state.call("atlantic_city"), deck)
    cards.zip(base).each do |actual, original|
      next if original.first == :advance
      monetary = [:collect, :pay, :collect_each, :pay_each].include?(original.first)
      wanted = if monetary
        [original.first, *original.drop(1).map { |n| (n * data[:salary] + 100) / 200 }]
      elsif original.first == :repairs
        [original.first, *original.drop(1).map { |n| n * factor }]
      else
        original
      end
      assert(actual == wanted, "#{id}: card adaptation changed a distance or missed a fee")
    end
  end
  targets = game.send(:card_definitions, state, :chance).select { |card| card.first == :advance }.map(&:last)
  assert(targets == (size == 60 ? [59, 0, 34, id == "indonesia" ? 51 : 11, 5] : [39, 0, 24, 11, 5]),
    "#{id}: cards still target the wrong board landmarks")
  assert(board[4][:amount] == data[:salary] && board[38][:amount] == (data[:salary] + 1) / 2,
    "#{id}: taxes are unrelated to board income")
  assert(game.send(:monopoly_cash_reserve, state, "Alice") == (data[:salary] + 1) / 2,
    "#{id}: bot ignores the local cost of fees")

  # Exercise the actual card effect, including history and landing resolution.
  state = new_state.call(id)
  state[:positions]["Alice"] = 36
  state[:card_decks] = { chance: [0], community: [1] }
  history = []
  game.send(:draw_event_card, state, "Alice", :chance, 8, history)
  assert(state[:positions]["Alice"] == size - 1 && state[:phase] == :property_decision,
    "#{id}: adapted advance card was not executed")
  assert(history.any? { |entry| entry.text.include?(board.last[:name]) }, "#{id}: card announces another edition's street")
  game.send(:draw_event_card, state, "Alice", :community, 9, [])
  assert(state[:cash]["Alice"] == cash + data[:salary], "#{id}: adapted award was not paid")
end

twelve = new_state.call("twelve_nations")
assert(twelve[:board_data][:salary] == 500, "Twelve nations salary was incorrectly inferred as 400")
assert(new_state.call("europe")[:board_data][:salary] == 2_000_000, "Observed European salary changed")
assert(twelve[:board][3][:rents] == [8, 40, 120, 300, 600, 900], "Vienna rents differ from QC")
assert(twelve[:board][59].values_at(:price, :mortgage, :rents) == [1800, 900, [180, 900, 2700, 5600, 6800, 8000]],
  "Last extended deed differs from QC")
assert(twelve[:board].values_at(1, 8, 14, 23, 34, 37, 43, 47, 56).map { |s| s[:house_cost] } ==
  [100, 100, 200, 300, 400, 400, 500, 550, 800], "Observed construction samples differ from QC")
gray = twelve[:board].select { |square| square[:group] == "gray" }
assert(gray.map { |square| square[:house_cost] }.uniq == [gray.map { |square| square[:price] }.min / 2],
  "Unobserved gray building cost is not tied to its own properties")
repair_state = new_state.call("twelve_nations")
repair_state[:owners][56] = "Alice"
repair_state[:houses][56] = 1
repair_state[:card_decks] = { chance: [11], community: [] }
game.send(:draw_event_card, repair_state, "Alice", :chance, 10, [])
assert(repair_state[:cash]["Alice"] == 6900, "Costlier extension house paid the cheap-board repair fee")
repair_state[:houses][56] = 5
game.send(:draw_event_card, repair_state, "Alice", :chance, 11, [])
assert(repair_state[:cash]["Alice"] == 6500, "Costlier extension hotel repair fee is inconsistent")

# The extra supply is usable, but the larger bank is still finite.
twelve[:cash]["Alice"] = 100_000
twelve[:owners][1] = twelve[:owners][3] = "Alice"
other_properties = twelve[:board].select { |s| s[:type] == :property && ![1, 3].include?(s[:index]) }
other_properties.first(8).each { |s| twelve[:houses][s[:index]] = 4 }
assert(game.send(:can_build?, twelve, "Alice", twelve[:board][1]), "60-square board still stops at 32 houses")
other_properties.first(12).each { |s| twelve[:houses][s[:index]] = 4 }
assert(!game.send(:can_build?, twelve, "Alice", twelve[:board][1]), "48-house stock not enforced")
twelve[:houses].clear
twelve[:houses][1] = twelve[:houses][3] = 4
other_properties.first(12).each { |s| twelve[:houses][s[:index]] = 5 }
assert(game.send(:can_build?, twelve, "Alice", twelve[:board][1]), "60-square board still stops at 12 hotels")
other_properties.first(18).each { |s| twelve[:houses][s[:index]] = 5 }
assert(!game.send(:can_build?, twelve, "Alice", twelve[:board][1]), "18-hotel stock not enforced")

# Currency conversion must not change the bot's strategy just because numbers grow.
%w[atlantic_city czechia europe].each do |id|
  state = new_state.call(id)
  factor = state[:board_data][:money_factor]
  state[:cash]["Alice"] = 550 * factor
  state[:phase] = :property_decision
  state[:positions]["Alice"] = 39
  assert(game.bot_action_score(view.call(state), "Alice", { "action" => "buy" }) == 500, "#{id}: bot misreads scaled buying reserve")
  state[:cash]["Alice"] = 430 * factor
  assert(game.bot_action_score(view.call(state), "Alice", { "action" => "buy" }) == -20, "#{id}: bot spends its scaled reserve")
  assert(game.send(:monopoly_cash_reserve, state, "Alice") == 100 * factor, "#{id}: wrong cash reserve")
end

# Replay through the same actions as a human, in each regional edition.
expected.each_key do |id|
  session = { "options" => JSON.generate(game.normalize_options("board" => id)) }
  events = []
  replay = game.replay(session, events, repository)
  24.times do
    break if replay.winner
    actor = replay.current_player
    actions = game.legal_actions(replay, actor)
    assert(!actions.empty?, "#{id}: active game has no actions")
    selected = actions.max_by { |a| game.bot_action_score(replay, actor, a) }
    replay = append_action(game, session, repository, events, replay, actor, selected, context_for)
    assert(replay.accepted_events.size == events.size, "#{id}: locally legal bot action rejected by replay")
  end
  duplicate = game.replay(session, events, repository)
  assert(replay.state == duplicate.state && replay.history == duplicate.history, "#{id}: nondeterministic replay")
end

poland = new_state.call("poland")
assert(poland[:board].size == 40 && poland[:cash]["Alice"] == 1500 && poland[:board][1][:name] == "Konopacka",
  "Custom Polish edition was replaced with an invented QC board")
puts "Monopoly: 18 regional profiles, custom Polish board, economy, supply, bots and replay passed."
