require_relative '../../support/ui'
require_relative '../../support/word_picker'
require_relative '../../../lib/game_surfaces'
require_relative '../../../games/scrabble'

def assert(value, message); raise message unless value; end
def n_(a, b, n); n == 1 ? a : b; end
game = GameRoomGames::Scrabble.new
state = game.initial_state(%w[Alice Bob], game.normalize_options('content_language_id' => 'en'))
tiles = game.tiles(state)
blank = tiles.index { |t| t[:letter].empty? }
ids = %w[g a t].map { |l| tiles.index { |t| t[:letter] == l } }
state.merge!(phase: :playing, current_player: 'Alice', turn: 1, revision: 1,
  racks: {'Alice' => [*ids, blank], 'Bob' => []})
replay = GameRoomGames::Replay.new(players: state[:players], current_player: 'Alice', state: state, history: [])
surface = GameSurfaces.build(game.surface_spec(replay, 'Alice'))
field = surface.fields.first
before = Marshal.dump(state)
surface.handle_command('word_place', 'slot' => 0)
assert(surface.state['draft'] == [[ids[0], 112, 'g']], 'direct slot did not place at cursor')
assert($spoken_messages.last == 'G, H8, 2 points, draft', "wrong occupied field: #{$spoken_messages.last}")
assert(field.logical_position == [7, 7], 'direct placement moved cursor')
surface.handle_command('word_place', 'slot' => 1)
assert(surface.state['draft'].size == 1, 'occupied field overwritten')
field.set_logical_position(8, 7)
surface.handle_command('word_place', 'slot' => 0)
assert(surface.state['draft'].size == 1, 'used tile placed twice')
surface.handle_command('word_read', 'slot' => 0)
assert($spoken_messages.last == 'G, 2 points, in the draft', 'plain digit stopped reading')
surface.handle_command('word_place', 'slot' => 1)
assert(surface.state['draft'].last == [ids[1], 113, 'a'], 'slots collapsed after tile use')
field.set_logical_position(9, 7)
WordPickerTest.answers << nil
surface.handle_command('word_place', 'slot' => 3)
assert(surface.state['draft'].size == 2, 'cancelled blank placed')
WordPickerTest.answers << game.language(state).alphabet.index('z')
surface.handle_command('word_place', 'slot' => 3)
assert($spoken_messages.last == 'Z, J8, 0 points, blank, draft', 'blank not identified')
assert(Marshal.dump(state) == before, 'unsubmitted placement changed model')
surface.handle_command('word_cancel')
surface.handle_command('word_sort')
sorted = surface.state['order']
field.set_logical_position(7, 7)
slot = sorted.index(ids[1])
surface.handle_command('word_place', 'slot' => slot)
assert(surface.state['draft'].first[0] == ids[1], 'direct slot ignores rack sorting')
surface.handle_command('word_remove')
assert($spoken_messages.last.start_with?('H8, empty'), 'empty field order changed')
[6, -1, 7, nil, '0'].each { |i| surface.handle_command('word_place', 'slot' => i) }
assert(surface.state['draft'].empty?, 'invalid/empty slot placed')
state[:board][112] = {letter: 'g', points: 2, blank: false}
surface.update_spec(game.surface_spec(replay, 'Alice'))
field.focus(nil, nil, true, include_header: false)
assert($spoken_messages.last == 'G, H8, 2 points', 'committed letter order differs')
state[:board][112] = nil
WordPickerTest.answers << ->(form) {
  state[:revision] += 1
  surface.update_spec(game.surface_spec(replay, 'Alice'))
  form.accept_button.trigger(:press)
}
surface.handle_command('word_place', 'slot' => surface.state['order'].index(blank))
assert(surface.state['draft'].empty?, 'stale blank choice placed')
%w[Bob Watcher].each do |viewer|
  other = GameSurfaces.build(game.surface_spec(replay, viewer))
  other.handle_command('word_place', 'slot' => 0)
  assert(other.state['draft'].empty?, 'non-current player placed')
end
shortcuts = game.game_shortcuts(replay, 'Alice')
(1..7).each do |n|
  keys = shortcuts.select { |s| s.key == n.to_s }
  assert(keys.any? { |s| s.action_name == 'word_place' && s.modifiers == [:shift] && s.payload['slot'] == n-1 }, 'missing Shift digit')
  assert(keys.any? { |s| s.action_name == 'word_read' }, 'missing ordinary digit')
end
assert(WordPickerTest.answers.empty?, 'unexpected picker opened')
puts 'PASS Scrabble direct placement, sort, guards, blank/stale choice and letter-coordinate-value speech'
