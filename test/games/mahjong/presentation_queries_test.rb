require_relative '../../support/game_option_editor_native'
require_relative '../../support/assertions'
require_relative '../../support/mahjong_round'
require_relative '../../support/mahjong_added_kong'
require_relative '../../../games/mahjong_support/table_presentation'
include GameRoomTest::Assertions
include MahjongRoundFixture
include MahjongAddedKongFixture

class MahjongPresentationQueriesGame < GameRoomGames::Base
  include GameRoomGames::MahjongTablePresentation
end

game = MahjongPresentationQueriesGame.new
players = %w[Alice Bob Carol Dave]
ready = ready_flow('123m456p789s1112z', '5z', self_draw: true)
kong = ready_flow('1111m234m567p789s', '5z', self_draw: true)
kong = GameRoomMahjong::TileFlow.new(hands: kong.hands, wall: kong.wall.drop(1),
  reserve: kong.wall.first(1), seat: 0, phase: :discard,
  last_draw: kong.last_draw, draw_origin: :normal)
cases = [
  [GameRoomMahjong::TableRound.new(flow: ready, variant: 'riichi', dealer: 0), 'Alice', 'riichi', :riichi_discards],
  [GameRoomMahjong::TableRound.new(flow: kong, variant: 'riichi', dealer: 1), 'Alice', 'concealed_kongs', :concealed_kongs],
  [GameRoomMahjong::TableRound.new(flow: added_kong_flow, variant: 'mcr', dealer: 0), 'Bob', 'added_kongs', :added_kongs]
]
queries = %i[concealed_kongs added_kongs riichi_discards]
cases.each do |round, viewer, part_id, query|
  expected = round.public_send(query).map(&:to_s)
  assert(!expected.empty?, "Fixture must expose #{part_id}")
  before = Marshal.dump(round)
  counts = Hash.new(0)
  trace = TracePoint.new(:call) do |call|
    counts[call.method_id] += 1 if call.self.equal?(round) && queries.include?(call.method_id)
  end
  spec = trace.enable { game.table_surface_spec(round, players: players, viewer: viewer) }
  assert_equal(expected, spec.parts.find { |part| part.id == part_id }.surface.options.map(&:value))
  queries.each { |method| assert_equal(1, counts[method], "Evaluate #{method} once per projection") }
  assert_equal(before, Marshal.dump(round), 'Projection must not mutate the round')
  counts.clear
  observer = trace.enable { game.table_surface_spec(round, players: players, viewer: 'Observer') }
  assert_equal({}, counts, 'Observers do not enumerate private action choices')
  assert(observer.parts.none? { |part| %w[hand claims commands riichi concealed_kongs added_kongs].include?(part.id) })
end
puts 'PASS Mahjong presentation: each real action-choice query once, same values, unchanged round and observer boundary'
