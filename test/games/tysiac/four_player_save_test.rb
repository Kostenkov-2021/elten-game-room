require_relative '../../support/tysiac_four_player'
require_relative '../../../lib/saved_games'

class FourPlayerSaveMemory
  def initialize; @data = {}; end
  def read_json(_path, default:); JSON.parse(JSON.generate(@data)); end
  def update_json(_path, default:); yield @data; end
end

def check_four_player_save(fixture, replace: false)
  game, events = fixture.game, Marshal.load(Marshal.dump(fixture.events))
  session = fixture.session.dup
  players = fixture.players.dup
  original = fixture.replay
  bot = GameRoomParticipants.bot_id(10, 1, name_token: 'pl20')
  if replace
    boundary = events.last.fetch('id') + 1
    players[1] = bot
    session.merge!('__initial_players' => fixture.players,
      '__players' => players, '__seat_changes' => [{'id' => boundary, 'players' => players}])
  end
  repository = GameRoomSavedGameArchive::ReplayRepository.new
  replay = game.replay(session, events, repository)
  assert(replay.accepted_events.length == events.length, 'replacement rejected old moves')
  assert(replay.history.map(&:to_h) == original.history.map(&:to_h), 'replacement rewrote historical names') if replace
  assert(replay.state[:hands][players[1]] == original.state[:hands][fixture.players[1]], 'replacement changed hand')
  if original.state[:teams].any?
    assert(replay.state[:teams][players[1]] == original.state[:teams][fixture.players[1]], 'replacement changed team')
    assert(replay.state[:scores] == original.state[:scores], 'replacement changed shared scores')
  end
  saves = SavedGames.new(FourPlayerSaveMemory.new, owner: 'Alice')
  row = saves.put(game: game, table: {'owner' => 'Alice', 'name' => 'Four-player save'},
    snapshot: Struct.new(:session, :events).new(session, events), repository: repository, now: 1_800_000_000)
  restored = saves.restored_data(row, game: game, table_id: 200, now: 1_800_010_000)
  next_session = session.merge('__players' => restored[:players], '__initial_players' => restored[:initial_players],
    '__seat_changes' => restored[:seat_changes])
  result = game.replay(next_session, restored[:events], repository)
  expected = JSON.generate(replay.state)
  expected = expected.gsub(bot, GameRoomParticipants.bot_id(200, 1, name_token: 'pl20')) if replace
  assert(JSON.parse(expected) == JSON.parse(JSON.generate(result.state)), 'restoration changed state')
  actor = result.current_player
  if actor
    action = game.legal_actions(result, actor).find { |item| item['action'] != 'surrender' }
    status, plan = game.action_for(action, result, actor, context: context_for)
    assert(status == :ok, 'restored next action unavailable')
    next_id = ([*restored[:events].map { |item| item['id'] }, *restored[:seat_changes].map { |item| item['id'] }].max || 0) + 1
    continuation = restored[:events] + plan.events.each_with_index.map do |item, index|
      {'id' => next_id + index, 'actor' => actor, 'action' => item.action, 'value' => item.value}
    end
    later = game.replay(next_session, continuation, repository)
    assert(later.accepted_events.length == continuation.length, 'restored next action rejected')
  end
end

%w[four_players teams].each do |variant|
  fixture = FourPlayerTysiacFixture.new(variant: variant, seats: [0, 0, 1, 1])
  fixture.next_deal
  [false, true].each { |replace| check_four_player_save(fixture, replace: replace) }
  fixture.finish_auction
  until fixture.replay.state[:phase] == :contract
    [false, true].each { |replace| check_four_player_save(fixture, replace: replace) }
    fixture.move(fixture.game.legal_actions(fixture.replay, fixture.replay.current_player).find { |a| a['kind'] == 'card' })
  end
  [false, true].each { |replace| check_four_player_save(fixture, replace: replace) }
  fixture.move({'kind' => 'command', 'action' => 'contract', 'bid' => 100})
  fixture.move(fixture.game.legal_actions(fixture.replay, fixture.replay.current_player).find { |a| a['card'].start_with?('normal|') })
  [false, true].each { |replace| check_four_player_save(fixture, replace: replace) }
end
puts 'PASS four-player/team saves: bidding, partial passing, contract, trick, human-to-bot replacement and restored continuation'
