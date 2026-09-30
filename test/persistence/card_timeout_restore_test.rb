require_relative "../support/card_timeout_restore"

[[GameRoomGames::NinetyNine, {}], [GameRoomGames::Poker, {"variant"=>"holdem"}],
 [GameRoomGames::Poker, {"variant"=>"draw"}], [GameRoomGames::Makao, {}]].each do |type, options|
  game = type.new
  bot = GameRoomParticipants.bot_id(10, 1, name_token: "pl20")
  c = TimedCardCase.new(game, options, ["A", bot])
  if game.id == "poker" && options["variant"] == "draw"
    c.act({"action"=>"all_in", "amount"=>995})
    c.act({"action"=>"call", "amount"=>995})
    assert(c.replay.state[:phase] == :exchange, "archive must cover all-in exchange")
  end
  storage = TimedArchiveMemory.new
  saves = SavedGames.new(storage, owner: "A")
  snapshot = Struct.new(:session, :events).new(c.session, c.events)
  row = saves.put(game: game, table: {"owner"=>"A", "name"=>"Timer test"}, snapshot:snapshot, repository:c.repo, now:110)
  assert(row["events"].map { |e| e["value"] } == c.events.map { |e| e["value"] }, "archive changed clock envelope")
  assert(SavedGames.new(storage, owner:"A").list == [row], "archive was not durable")
  restored = saves.restored_data(row, game:game, table_id:88, now:1110)
  assert(restored[:players][1] != bot && GameRoomParticipants.bot_name_token(restored[:players][1]) == "pl20", "bot seat restore")
  session = {"options"=>row["options"], "__players"=>restored[:players], "__clock_offset"=>restored[:clock_offset]}
  repo = SavedGames::ReplayRepository.new
  replay = game.replay(session, restored[:events], repo)
  assert(replay.accepted_events.length == c.events.length && replay.state[:turn_deadline] == 120, "archive rejected timer or restarted it")
  assert(replay.state[:phase] == c.replay.state[:phase], "restore changed phase")
  assert(replay.state[:hands].values == c.replay.state[:hands].values, "restore changed cards")
  assert(replay.state[:clock_offset] == 1000, "restored pause not excluded")
  ctx = GameRoomGames::ActionContext.new(now:1119 - replay.state[:clock_offset])
  assert(!game.automatic_action_due?(replay, "A", context:ctx), "saved timeout fired early")
  ctx.now += 1
  assert(game.automatic_action_due?(replay, "A", context:ctx), "saved timeout never fired")
  selection = game.automatic_action(replay, "A", context:ctx)
  player = replay.current_player
  after = append_action(game, session, repo, restored[:events], replay, "A", selection, ctx)
  assert(after.accepted_events.length == c.events.length + 1, "restored timeout not accepted")
  if game.id == "poker" && options["variant"] == "draw"
    assert(after.state[:exchanged][player] && !after.state[:folded][player], "restored all-in was folded")
  end
end
puts "PASS timed archives: JSON save/validate/restore, renamed bot seat, remaining time, accepted timeout and all-in exchange; no files or live profiles changed"
