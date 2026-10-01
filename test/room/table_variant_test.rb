require_relative "../support/table_watch_runtime"
registry = EltenGameRoom::GAME_REGISTRY
empty = %w[mexican_train war scientific_war battleship ludo reversi yahtzee biblios chess four_in_a_row tic_tac_toe]
registry.ids.each do |id|
  game = registry.build(id)
  options = game.default_options.merge("__secret" => "secret", "thinking_time" => 123, "bot_delay" => 5, "full_p2p" => true)
  payload = GameRoomTableVariant.payload(game, JSON.generate(options))
  message = GameRoomTableVariant.text(game, payload)
  assert(message.encoding == Encoding::UTF_8 && message.valid_encoding?, "invalid variant encoding: #{id}")
  assert((payload["options"].keys & %w[__secret thinking_time bot_delay full_p2p]).empty?, "private/unwanted option: #{id}")
  if empty.include?(id)
    assert(message.empty?, "unwanted description: #{id}: #{message}")
  else
    assert(!message.empty?, "missing agreed variant: #{id}")
  end
  assert(GameRoomTableVariant.text(game, nil) == "" && GameRoomTableVariant.text(game, {"format" => 1, "options" => {}}) == "", "absent options became defaults")
  puts "#{id}: #{message}"
end
read = ->(id, options) { GameRoomTableVariant.text(registry.build(id), GameRoomTableVariant.payload(registry.build(id), options)) }
assert(read.call("spades", {"quicksand" => true, "team_size" => 2, "score_limit" => 500}) == "Quicksand", "Spades includes team or score")
assert(!read.call("poker", registry.build("poker").default_options).match?(/limit|chips|blind/i), "Poker extras")
assert(read.call("uno", {"deck" => "flip", "interceptions" => true}).include?("with interceptions"), "UNO interception missing")
assert(read.call("uno", {}).empty?, "UNO absent data guessed")
assert(read.call("domino", {"tile_set" => "2d6", "teams" => true}) == "2 × Double 6, Team play", "Domino description too detailed")
assert(read.call("axel_pong", {"team_size" => 2, "arcade" => true, "difficulty" => 3}) == "Doubles, Arcade, Hard", "Pong variant incomplete")
assert(read.call("krowa", {"variant" => "daily", "length" => 4}) == read.call("krowa", {"variant" => "daily"}), "Daily leaked meaningless length")
[nil, 1, [], "broken", {"format" => 9}, {"format" => 1, "options" => []}].each do |payload|
  assert(GameRoomTableVariant.text(registry.build("uno"), payload).empty?, "malformed metadata not ignored")
end
puts "PASS recipient-side short variants: all games, exact exclusions, missing/malformed options, no internal payload"
