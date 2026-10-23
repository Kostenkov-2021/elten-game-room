require_relative '../../support/duck_challenge_native'
require_relative '../../support/farkle'
require_relative '../../../lib/game_layout'
require_relative '../../../lib/game_screen'

module Session
  def self.name; 'Alice'; end
end
DuckChallengeNativeDriver.new
game = GameRoomGames::Farkle.new
repository = FarkleRepository.new(%w[Alice Bob])
session = {'__id'=>1, 'options'=>JSON.generate(game.normalize_options(
  'score_limit'=>100, 'entry_minimum'=>0, 'turn_minimum'=>0))}
events = [farkle_event(1,'Alice','roll','1,2,3,4,5,6'),
  farkle_event(2,'Alice','keep','0,1,2,3,4,5'), farkle_event(3,'Alice','bank'),
  farkle_event(4,'Bob','roll','2,2,3,3,4,6')]
replay = game.replay(session, events, repository)
assert(replay.finished? && replay.winner == 'Alice' && replay.accepted_events.size == 4,
  'The fixture must finish through accepted ordinary game events')

%w[Alice Bob Observer].each do |viewer|
  spec = game.game_view_spec(replay, viewer)
  assert(spec.surface.zones.all? { |zone| zone.cards.empty? }, 'Finished game offers Roll or Bank')
  assert(game.result_text(replay) == spec.surface.zones.first.empty_label, 'Finished surface lost the result')
  layout = GameRoomLayout::Screen.new(view_spec: spec, history_items: [], user_items: %w[Alice Bob],
    users_header: 'Users', phase: :finished, own_table: viewer == 'Alice')
  list = layout.surface.fields.find { |field| field.is_a?(EltenAPI::Controls::ListBox) }
  assert(list, 'Missing native game surface')
  screen = GameScreen.allocate
  screen.instance_variable_set(:@session, session)
  screen.instance_variable_set(:@layout, layout)
  screen.define_singleton_method(:event_presentation_busy?) { false }
  wait = GameScreen::WaitState.new(replay: replay, session: session, actor: viewer)
  screen.send(:bind_wait_surface, wait, layout, -> {})
  list.trigger(:select, 0)
  assert(wait.action.nil?, 'Finished native surface emitted an unusable game action')
  assert(game.legal_actions(replay, viewer).empty?, 'Finished game still has legal moves')
end
puts 'PASS finished Farkle: accepted complete replay, native layout/binding, owner, guest and observer; no Roll/Bank action'
