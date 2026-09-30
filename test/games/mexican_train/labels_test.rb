# encoding: UTF-8
require 'json'
require_relative "../../support/ui"
require_relative "../../support/localization"
require_relative "../../../lib/game_surfaces"
require_relative "../../../games/mexican_train"

def assert(value, message); raise message unless value; end

game = GameRoomGames::MexicanTrain.new
state = game.initial_state(%w[Alice Bob], game.default_options)
state.merge!(phase: :playing, round: 1, turn: 1, current_player: 'Alice',
  hands: {'Alice' => %w[9c0 330], 'Bob' => %w[440]}, station: 12,
  trains: {
    'p0' => {owner: 'Alice', end: 9, open: false, chain: [{tile: 'bc0', left: 12, right: 11}, {tile: '9b0', left: 11, right: 9}]},
    'p1' => {owner: 'Bob', end: 7, open: true, chain: [{tile: '7c0', left: 12, right: 7}]},
    'm' => {owner: nil, end: 12, open: true, chain: []}}, pending: [])
replay = GameRoomGames::Replay.new(players: state[:players], current_player: 'Alice', state: state, history: [])
before = Marshal.dump(state)

[false, true].each do |polish|
  GameRoomTestLocalization.use_language(polish ? :pl : :en)
  spec = game.surface_spec(replay, 'Alice')
  expected = polish ? ['Alice, 9, zamknięty', 'Bob, 7, otwarty', 'Pociąg meksykański, 12'] : ['Alice, 9, closed', 'Bob, 7, open', 'Mexican train, 12']
  surface = GameSurfaces.build(spec)
  shortcut = game.custom_game_shortcuts(replay, 'Alice').find { |item| item.key == 'c' && item.modifiers.empty? }
  surface.handle_command(shortcut.action_name, shortcut.payload)
  assert(surface.fields.first.header == (polish ? 'Pociągi' : 'Trains'), 'C header still contains the station')
  assert(surface.fields.first.options == expected, 'train labels contain an unnecessary end prefix')
  assert(spec.table.first[:items].first == '12–12', 'station removed from the actual detailed chain')
  surface.cancel_pending_action!
  surface.fields.first.trigger(:select, [0])
  assert(surface.fields.first.options == ['Alice, 9', polish ? 'Pociąg meksykański, 12' : 'Mexican train, 12', 'Bob, 7'], 'destination choices must retain concise labels for all trains')
  assert(spec.zones.first.cards.first.choices.map(&:id) == %w[p0 m p1], 'destination list must show all trains, even when the tile does not fit')
  assert(Marshal.dump(state) == before, 'display mutated game state')
end

state[:pending] = ['p0']
state[:trains]['p0'][:chain] << {tile: '990', left: 9, right: 9}
spec = game.surface_spec(replay, 'Alice')
assert(spec.table.first[:label] == 'Alice, 9, zamknięty, dublet do zamknięcia', 'unfinished double marker lost')
state[:station] = 0
assert(game.surface_spec(replay, 'Alice').table_header == 'Pociągi', 'station zero leaks into header')
puts 'Mexican Train labels: concise C header and destinations, PL/EN, open state and double obligation retained: OK'
