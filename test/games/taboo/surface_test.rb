require_relative "../../support/ui"
require_relative "../../../lib/game_surfaces"
require_relative "../../../games/taboo"
def assert(value,message); raise message unless value; end
game = GameRoomGames::Taboo.new
state = game.initial_state(%w[A B C D], game.normalize_options({}))
state.merge!(phase: :describing, team: 0, current_player: "A", card: 0, turn: 1, serial: 1, deadline: Time.now.to_i+30)
replay = GameRoomGames::Replay.new(board: [],players: state[:players],current_player: "A",state: state,history: [],accepted_events: [])
surface = GameSurfaces.build(game.surface_spec(replay,"A"))
assert(!GameSurfaces.hand_surface?(game.surface_spec(replay,"A")),"not a card hand")
assert(surface.fields.first.options.length == 6,"target plus five restrictions")
assert(surface.take_cursor_announcement(0).include?(game.cards(state)[0]['word']),"initial card read")
events = []
surface.on_action { |a| events << a }
surface.fields.first.trigger(:select)
assert(events.last.name == 'correct' && events.last.payload['token'] == game.token(state),"Enter binds shown card")
old_action = surface.handle_command('taboo_skipped')
state[:serial] += 1
state[:card] = 1
surface.update_spec(game.surface_spec(replay,'A'))
assert(old_action.payload['token'] != game.token(state),"action retains previous token")
assert(surface.fields.first.index == 0 && surface.take_cursor_announcement(0).include?(game.cards(state)[1]['word']),"new card starts at target")
state[:serial] += 1
surface.update_spec(game.surface_spec(replay,'A'))
assert(surface.take_cursor_announcement(nil) == nil && surface.take_cursor_announcement(0) == nil,"no deferred interruption after chat")
%w[C watcher].each do |viewer|
  other = GameSurfaces.build(game.surface_spec(replay,viewer))
  assert(other.fields.first.options.length == 1 && other.take_cursor_announcement(0) == nil,"guesser and observer privacy")
  assert(other.handle_command('taboo_buzzed') == true,"cannot buzz")
end
opponent = GameSurfaces.build(game.surface_spec(replay,'B'))
assert(opponent.handle_command('taboo_buzzed').name == 'buzzed',"opponent buzzer")
state[:master] = 'watcher'
state[:phase] = :review
state[:review] = [{ card: 0, result: 'neutral', actor: 'A' }]
assert(GameSurfaces.build(game.surface_spec(replay,'watcher')).fields.length == 3,"observing master can review and restart")
assert(GameSurfaces.build(game.surface_spec(replay,'A')).fields.length == 1,"first player is not necessarily master")
state[:phase] = :describing
state[:master] = 'A'
options = {view_spec: game.game_view_spec(replay, 'A'), history_items: [], user_items: [], users_header: 'Users', phase: :active}
layout = GameRoomLayout::Screen.new(**options)
original = layout.surface
layout.take_cursor_announcement
layout.update(**options.merge(view_spec: game.game_view_spec(replay, 'A')))
assert(layout.surface.equal?(original), 'a routine layout refresh must preserve the card control')
assert(layout.take_cursor_announcement == nil, 'a routine layout refresh must not repeat the whole card')
state[:phase] = :review
layout.update(**options.merge(view_spec: game.game_view_spec(replay, 'A')))
assert(layout.surface.equal?(original) && original.fields.length == 3, 'review buttons must appear while retaining the surface')
puts 'Taboo surface, role privacy, cursor, chat and moderation: OK'
