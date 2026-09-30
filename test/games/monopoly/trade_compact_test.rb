require_relative "../../support/new_games_fixture"

players = %w[Alice Bob Carol Dave]
repository = NewGames116Repository.new(players)
game = GameRoomGames::Monopoly.new
checks = 0

check = lambda do |name, &block|
  block.call
  checks += 1
  puts "OK: #{name}"
end

check.call("compact offers cover every tradable property on the largest board") do
  large_board = GameRoomContent::MonopolyBoards.choices.find do |choice|
    GameRoomContent::MonopolyBoards.build(choice.value)[:squares].length == 60
  end
  state = game.send(:initial_state, players, game.normalize_options("board" => large_board.value))
  tradable = state[:board].select { |square| [:property, :railroad, :utility].include?(square[:type]) }
  give = tradable.each_with_index.filter_map { |square, index| square[:index] if index.even? }
  receive = tradable.each_with_index.filter_map { |square, index| square[:index] if index.odd? }
  value = game.send(:encode_trade_offer, target: 1, give_properties: give,
    receive_properties: receive, give_cash: 99_999_999, receive_cash: 99_999_998)
  decoded = game.send(:parse_trade_offer, state, value)
  assert(value.length <= 64, "compact trade is #{value.length} characters")
  assert(decoded[:target] == "Bob", "compact target changed")
  assert(decoded[:give_properties] == give && decoded[:receive_properties] == receive, "property masks changed")
  assert(decoded[:give_cash] == 99_999_999 && decoded[:receive_cash] == 99_999_998, "cash changed")

  single_value = game.send(:encode_trade_offer, target: 1, give_properties: [tradable.first[:index]],
    receive_properties: [], give_cash: 0, receive_cash: 10)
  single = game.send(:parse_trade_offer, state, single_value)
  assert(single[:give_properties] == [tradable.first[:index]] && single[:receive_properties].empty?,
    "a one-property offer changed during compact encoding")
end

check.call("one and many properties replay identically for several readers") do
  base = game.send(:initial_state, players, game.default_options)
  base[:cash].transform_values! { 10_000 }
  base[:owners].merge!(1 => "Alice", 3 => "Alice", 6 => "Bob", 8 => "Bob")
  value = game.send(:encode_trade_offer, target: 1, give_properties: [1, 3],
    receive_properties: [6, 8], give_cash: 250, receive_cash: 125)
  snapshots = 4.times.map do
    state = Marshal.load(Marshal.dump(base))
    history = []
    offer_event = { "id" => 11, "action" => "trade_offer", "value" => value }
    assert(game.send(:apply_trade, state, offer_event, "Alice", repository, history), "valid offer rejected")
    accept_event = { "id" => 12, "action" => "trade_accept", "value" => "" }
    assert(game.send(:apply_trade, state, accept_event, "Bob", repository, history), "valid acceptance rejected")
    [state[:cash], state[:owners], history.map(&:text)]
  end
  assert(snapshots.uniq.length == 1, "readers reconstructed different trades")
end

check.call("preparing a trade is public but does not advance the turn") do
  state = game.send(:initial_state, players, game.default_options)
  state[:phase] = :turn_complete
  history = []
  event = { "id" => 20, "action" => "trade_prepare", "value" => "1" }
  assert(game.send(:apply_trade, state, event, "Alice", repository, history), "preparation rejected")
  assert(state[:phase] == :turn_complete && state[:current_player] == "Alice", "preparation advanced the game")
  assert(history.last.text == "Alice is preparing a trade offer for Bob.", "preparation is not announced")
end

check.call("empty and invalid trade forms have specific results") do
  state = game.send(:initial_state, players, game.default_options)
  replay = GameRoomGames::Replay.new(players: players, current_player: "Alice", winner: nil,
    accepted_events: [], history: [], state: state)
  status, = game.action_for({ "action" => "trade_offer", "target" => 1,
    "give_properties" => [], "receive_properties" => [], "give_cash" => "0", "receive_cash" => "0" }, replay, "Alice")
  assert(status == :empty_trade, "empty form returned #{status}")
  status, = game.action_for({ "action" => "trade_offer", "target" => 99,
    "give_properties" => [], "receive_properties" => [], "give_cash" => "1", "receive_cash" => "0" }, replay, "Alice")
  assert(status == :invalid_trade, "invalid target returned #{status}")
end

check.call("position and holdings lists include the agreed context") do
  state = game.send(:initial_state, players, game.default_options)
  state[:positions]["Alice"] = 3
  state[:owners].merge!(1 => "Alice", 3 => "Alice", 6 => "Bob")
  assert(game.send(:positions_text, state).include?("Alice: field 3, Baltic avenue"), "I omits field number")
  holdings = game.send(:property_choices, state, group_progress: true) { |square| state[:owners][square[:index]] == "Alice" }
  assert(holdings.any? { |choice| choice.label.include?("group 2 of 2") }, "holdings omit group ownership")
  trade_fields = game.send(:trade_form_fields, state, "Alice", "Bob")
  assert(trade_fields.flat_map { |field| field.choices.to_a }.none? { |choice| choice.label.match?(/group \d+ of \d+/) },
    "trade list unexpectedly includes holdings progress")
end

check.call("player and jackpot payments use natural wording") do
  state = game.send(:initial_state, players, game.default_options)
  player_text = game.send(:pay_and_describe, state, "Alice", "Bob", 28, "rent for Bond Street")
  assert(player_text == "Alice pays Bob 28: rent for Bond Street.", player_text)
  jackpot_text = game.send(:pay_and_describe, state, "Alice", :jackpot, 75, "Luxury Tax")
  assert(jackpot_text == "Alice pays 75 into the Free Parking pool: Luxury Tax.", jackpot_text)
end

puts "Monopoly compact trades and interface: #{checks} checks passed"
