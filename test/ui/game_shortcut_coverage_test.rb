require_relative "../support/ui"
require_relative "../../lib/game_surfaces"
require_relative "../../games/yahtzee"
require_relative "../../games/ludo"
require_relative "../../games/ninety_nine"
require_relative "../../games/monopoly"
require_relative "../../games/farkle"
require_relative "../../games/registry"
def assert(value,message); raise message unless value; end
def n_(a,b,n); n == 1 ? a : b; end
yahtzee = GameRoomGames::Yahtzee.new
state = yahtzee.send(:initial_state,%w[A B C],yahtzee.default_options)
state[:sheets]['A']['ones'] = 0
state[:dice] = [1,2,3,4,5]
state[:turn_rolls] = 1
replay = GameRoomGames::Replay.new(players: state[:players],current_player: 'A',state: state,history: [],accepted_events: [])
before = Marshal.dump(state)
keys = yahtzee.game_shortcuts(replay,'A')
assert(keys.find { |s| s.key == 'd' }.message == '1, 2, 3, 4, 5.','D reads raw values without a redundant prefix')
own = keys.find { |s| s.key == 'v' && s.modifiers.empty? }
assert(own.choices.any? { |c| c.label == 'Ones: 0' },'filled zero')
assert(own.choices.any? { |c| c.label == 'Twos: not filled' },'unused field')
assert(own.choices.any? { |c| c.label.start_with?('One pair:') },'variant categories')
assert(own.choices.any? { |c| c.label.start_with?('Additional Yahtzee bonuses:') },'bonuses')
others = keys.find { |s| s.key == 'v' && s.modifiers == [:shift] }
assert(others.choices.map(&:label) == %w[B C] && others.choices.all? { |c| c.value.is_a?(Array) },'choose opponent then sheet')
assert(yahtzee.game_shortcuts(replay,'observer').none? { |s| s.key == 'v' && s.modifiers.empty? },'no imaginary observer sheet')
assert(Marshal.dump(state) == before,'read-only sheet does not change state')
state[:options]['extra_categories'] = false
assert(yahtzee.score_sheet_choices(state,'A').none? { |c| c.label.start_with?('One pair:') },'hidden categories omitted')
ludo = GameRoomGames::Ludo.new
lr = GameRoomGames::Replay.new(players: %w[A B],current_player: 'A',state: {players: %w[A B], roll: 6, last_roll: 6, last_roll_player: 'A'})
assert(ludo.shortcut_feature_data(:last_roll,lr,'B')[:message] == 'A, 6.','Ludo D identifies the roller outside their turn')
lr.state[:last_roll] = nil
assert(ludo.shortcut_feature_data(:last_roll,lr,'A')[:message].include?('not been rolled'),'Ludo before roll')
assert(GameRoomGames::NinetyNine.new.name == '99' && GameRoomGames::NinetyNine.new.id == 'ninety_nine','stable 99 ID')
assert(GameRoomGames::Farkle.new.shortcut_features.include?(:last_roll),'Farkle D unchanged')
assert(!GameRoomGames::Monopoly.new.shortcut_features.include?(:last_roll),'Monopoly D not replaced')
names = %w[Żaba Zebra Łódź Las Ącki Ala Ćma Czapla 99 UNO Źrebak].shuffle
expected = %w[99 Ala Ącki Czapla Ćma Las Łódź UNO Zebra Źrebak Żaba]
assert(names.sort_by { |n| GameRoomGames::Registry.sort_key(n) } == expected,'Polish alphabetical ordering')
assert(names.map(&:b).sort_by { |n| GameRoomGames::Registry.sort_key(n) }.map { |n| n.force_encoding('UTF-8') } == expected,'binary-loaded game names must sort without an encoding error')
puts 'Dice reading, score sheets, game ordering and stable 99 ID: OK'
