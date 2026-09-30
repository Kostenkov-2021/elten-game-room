require_relative "../../support/tysiac_two_player"
require_relative "../../../lib/saved_games"

class TysiacSaveMemory
  def initialize; @data = {}; end
  def read_json(_path, default:); JSON.parse(JSON.generate(@data)); end
  def update_json(_path, default:); yield @data; end
end

def check_tysiac_archive(fixture)
  # Use an actual bot controller so restoration exercises seat remapping.
  bot = GameRoomParticipants.bot_id(10, 1, name_token: "pl20")
  players = ["Alice", bot]
  repository = NewGames116Repository.new(players)
  events = fixture.events.map { |event| event.merge("actor" => event["actor"] == "Bob" ? bot : "Alice") }
  session = fixture.session.merge("__players" => players)
  replay = fixture.game.replay(session, events, repository)
  assert(fixture.game.save_game_error(replay) == nil, "stable two-player phase cannot be saved")
  snapshot = Struct.new(:session, :events).new(session, events)
  storage = TysiacSaveMemory.new
  saves = SavedGames.new(storage, owner: "Alice")
  row = saves.put(game: fixture.game, table: { "owner" => "Alice", "name" => "Tysiac test" }, snapshot: snapshot,
    repository: repository, now: 1_800_000_000)
  assert(saves.list == [row], "archive not persisted")
  restored = saves.restored_data(row, game: fixture.game, table_id: 200, now: 1_800_010_000)
  assert(restored[:players].last == GameRoomParticipants.bot_id(200, 1, name_token: "pl20"), "bot identity not restored")
  next_bot = restored[:players].last
  result = fixture.game.replay(session.merge("__players" => restored[:players]), restored[:events], SavedGames::ReplayRepository.new)
  assert(result.accepted_events.length == events.length, "restore rejected new event type")
  # Compare the entire state after replacing only the remapped controller.
  expected = JSON.parse(JSON.generate(replay.state).gsub(bot, next_bot))
  actual = JSON.parse(JSON.generate(result.state))
  assert(actual == expected, "archive lost talon choice/discards/scoring option")
  current = result.current_player
  action = fixture.game.legal_actions(result, current).first
  assert(action, "restored game has no continuation")
  status, plan = fixture.game.action_for(action, result, current, context: context_for)
  assert(status == :ok, "restored game rejected continuation")
  continued = restored[:events].dup
  plan.events.each do |event|
    continued << { "id" => continued.length + 1, "actor" => current, "action" => event.action, "value" => event.value }
  end
  later = fixture.game.replay(session.merge("__players" => restored[:players]), continued, SavedGames::ReplayRepository.new)
  assert(later.accepted_events.length == continued.length, "restored continuation does not replay")
end

[2, 3].product([false, true]).each do |size, award|
  fixture = TwoPlayerTysiacFixture.new(size: size, award: award)
  fixture.auction
  check_tysiac_archive(fixture)
  fixture.choose(1)
  check_tysiac_archive(fixture)
  size.times do
    fixture.discard
    check_tysiac_archive(fixture)
  end
  fixture.move({ "kind" => "command", "action" => "contract", "bid" => 100 })
  fixture.move(fixture.game.legal_actions(fixture.replay, fixture.replay.current_player).first)
  check_tysiac_archive(fixture)
end

puts "PASS two-player Tysiac saves: choice, partial/full discard, contract, unfinished trick, both options and remapped bot"
