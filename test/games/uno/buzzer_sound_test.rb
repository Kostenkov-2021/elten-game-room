require_relative "../../support/ui"
require_relative "../../../games/uno"
require_relative "../../../lib/game_sounds"
require_relative "../../../lib/game_room_preferences"

def assert(value, message); raise message unless value; end

game = GameRoomGames::Uno.new
players = %w[Alice Bob]
state = game.send(:initial_state, players, game.normalize_options('buzzers' => true))
state.update(phase: :playing, current_player: 'Alice', colour: 'Y', discard: ['Y9a'],
  draw_pile: %w[R1a R2a R3a], hands: {'Alice' => %w[NB0 R7a], 'Bob' => %w[B1a G2a]})
make_replay = ->(value, history) { GameRoomGames::Replay.new(players: players, history: history,
  current_player: value[:current_player], accepted_events: [], state: value) }
repo = Object.new
def repo.event_id(event); event.fetch('id'); end
before = make_replay.call(Marshal.load(Marshal.dump(state)), [])
history = []
event = {'id' => 41, 'action' => 'play', 'value' => 'NB0', 'actor' => 'Alice'}
assert(game.send(:apply_play, state, event, 'Alice', repo, history), 'buzzer play was not accepted')
after = make_replay.call(state, history)
assert(state[:buzzer_active], 'buzzer window did not open')
cue = lambda do |row, viewer, previous = before, current = after|
  Array(GameRoomSounds.event_cue(game: game, event: row, before_replay: previous,
    after_replay: current, repository: repo, viewer: viewer))
end
[*players, 'Observer'].each do |viewer|
  assert(cue.call(event, viewer) == %w[play buzzer], "#{viewer}: card placement and buzzer must both sound")
end
assert(!cue.call(event.merge('id' => 42), 'Alice').include?('buzzer'), 'buzzer repeated without a matching accepted play')
assert(!cue.call({'id' => 43, 'action' => 'buzz'}, 'Bob').include?('buzzer'), 'response replayed the buzzer')
declared = make_replay.call(state, [GameRoomGames::HistoryEntry.new(key: 'uno:44', event_id: 44, kind: :game)])
assert(cue.call({'id' => 44, 'action' => 'uno'}, 'Alice', before, declared) == ['buzzer2'], 'saying UNO changed to the card sound')
program = Object.new
played = []
program.define_singleton_method(:play_sound_from_asset) { |name, **_options| played << name }
GameRoomSounds.play_event(program, game: game, event: event, before_replay: before,
  after_replay: after, repository: repo, viewer: 'Bob')
assert(played == %w[play buzzer], 'dispatcher did not play both effects')
program.define_singleton_method(:game_room_sound_enabled?) { |_name| false }
GameRoomSounds.play_event(program, game: game, event: event, before_replay: before,
  after_replay: after, repository: repo, viewer: 'Bob')
assert(played == %w[play buzzer], 'muted game sounds still played')
assert(GameRoomPreferences.sound_group('buzzer') == 'game', 'buzzer ignores game volume group')
asset = File.expand_path("../../../Audio/buzzer.opus", __dir__)
bytes = defined?(BinaryRulesLoad) ? BinaryRulesLoad.read(File.expand_path(asset)) : File.binread(asset)
assert(bytes.start_with?('OggS') && bytes.byteslice(0, 128).include?('OpusHead'), 'missing/invalid buzzer asset')
puts 'PASS UNO buzzer: accepted card, all players/observer, placement overlap, no response/rejection replay, UNO declaration unchanged, volume/mute'
