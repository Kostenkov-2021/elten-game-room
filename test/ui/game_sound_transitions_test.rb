require_relative "../support/ui"
require_relative "../../lib/game_sounds"
%w[uno rummy domino mexican_train ninety_nine monopoly poker farkle tysiac].each do |name|
  require_relative "../../games/#{name}"
end
def n_(one, many, count); count == 1 ? one : many; end
def assert(value, message); raise message unless value; end
def sound_replay(state, history = [])
  GameRoomGames::Replay.new(players: state[:players], current_player: state[:current_player], winner: state[:winner],
    draw: state[:draw] == true, accepted_events: [], state: state, history: history)
end
def copied(value); Marshal.load(Marshal.dump(value)); end
repo = Object.new
def repo.event_id(event); event.fetch("id"); end
players = %w[Alice Bob Carol]
sound = ->(game, event, before, after, viewer = "Alice") {
  Array(GameRoomSounds.event_cue(game: game, event: event, before_replay: before, after_replay: after, repository: repo, viewer: viewer))
}

# Actual accepted Ninety-Nine moves: jack effects and thresholds coexist.
game = GameRoomGames::NinetyNine.new
[[25, "0JC", "normal", %w[play reverse draw2]], [60, "0JC", "normal", %w[play reverse draw2]],
 [23, "0JC", "normal", %w[play reverse ninety3366]], [56, "0TC", "plus", %w[play ninety3366]],
 [33, "09C", "normal", %w[play]], [66, "0TC", "minus", %w[play]]].each_with_index do |(total, card, mode, expected), index|
  state = game.send(:initial_state, players, game.default_options)
  state.update(phase: :playing, total: total, current_player: "Alice", hands: { "Alice" => [card], "Bob" => ["02H"], "Carol" => ["03S"] })
  before = sound_replay(copied(state))
  history = []
  event = { "id" => index + 1, "action" => "play", "actor" => "Alice", "value" => "#{card}|#{mode}" }
  assert(game.send(:apply_play, state, event, "Alice", repo, history), "99 fixture rejected #{event}")
  actual = sound.call(game, event, before, sound_replay(state, history))
  assert(actual == expected, "99 cues #{actual.inspect}, expected #{expected.inspect}")
end

# Real banking, including computers, failure and a simultaneous party result.
game = GameRoomGames::Farkle.new
["Alice", "bot:1:1"].each do |actor|
  state = game.send(:initial_state, [actor, "Bob"], game.default_options)
  state[:turn_points] = 1000
  state[:dice_to_roll] = 3
  before = sound_replay(copied(state))
  event = { "id" => 50, "actor" => actor, "action" => "bank", "value" => "" }
  history = []
  assert(game.send(:apply_bank, state, event, actor, repo, history), "bank rejected")
  assert(sound.call(game, event, before, sound_replay(state, history), "Bob").include?("farkle_bank"), "missing bank cue")
  assert(!sound.call(game, event, before, before, "Bob").include?("farkle_bank"), "rejected bank sounds")
  state[:winner] = actor
  assert(sound.call(game, event, before, sound_replay(state, history), actor) == %w[farkle_bank win_party], "bank masks party result")
end

# Marriage cues use the accepted play, not possession of king/queen or a
# rejected declaration. All suits, local/remote/bot, participants/observers.
game = GameRoomGames::Tysiac.new
%w[H S D C].each do |suit|
  ["Alice", "bot:1:1"].each do |actor|
    state = game.send(:initial_state, [actor, "Bob", "Carol"], game.default_options)
    state.update(phase: :playing, current_player: actor, trick_number: 1, hands: { actor => ["K#{suit}", "Q#{suit}"], "Bob" => ["AS"], "Carol" => ["AH"] })
    before = sound_replay(copied(state))
    history = []
    event = { "id" => 60, "actor" => actor, "action" => "play", "value" => "marriage|K#{suit}" }
    assert(game.send(:apply_play, state, event, actor, repo, history), "marriage rejected")
    [actor, "Bob", "Observer"].each do |viewer|
      assert(sound.call(game, event, before, sound_replay(state, history), viewer) == %w[play draw2 1000_mariage], "marriage layering/audience")
    end
    assert(!sound.call(game, event, before, before).include?("1000_mariage"), "rejected marriage cue")
    ordinary = event.merge("value" => "normal|K#{suit}")
    assert(!sound.call(game, ordinary, before, sound_replay(state, history)).include?("1000_mariage"), "ordinary king sounds marriage")
  end
end

# Every permanent elimination family, including team domino and both poker
# variants. Earlier elimination must remain silent at the final game result.
[GameRoomGames::Uno, GameRoomGames::Rummy, GameRoomGames::NinetyNine,
 GameRoomGames::Domino, GameRoomGames::MexicanTrain, GameRoomGames::Monopoly].each do |type|
  game = type.new
  state = game.send(:initial_state, players, game.default_options)
  before = sound_replay(copied(state))
  field = game.id == "monopoly" ? :bankrupt : :eliminated
  state[field]["Alice"] = true
  after = sound_replay(copied(state))
  assert(GameRoomSounds.result_cue(game, before, after, "Alice") == "lose_party", "no early loss #{game.id}")
  assert(GameRoomSounds.result_cue(game, after, after, "Alice") == nil, "repeated elimination #{game.id}")
  assert(GameRoomSounds.result_cue(game, before, after, "Bob") == nil, "wrong audience #{game.id}")
  assert(GameRoomSounds.result_cue(game, nil, after, "Alice") == nil, "history elimination #{game.id}")
  state[:winner] = "Bob"
  state[:winners] = ["Bob"]
  final = sound_replay(state)
  assert(GameRoomSounds.result_cue(game, after, final, "Alice") == nil, "second party loss #{game.id}")
  assert(GameRoomSounds.result_cue(game, before, final, "Bob") == "win_party", "winner #{game.id}")
  assert(GameRoomSounds.result_cue(game, before, final, "Observer") == nil, "observer result #{game.id}")
end
game = GameRoomGames::Uno.new
state = game.send(:initial_state, players, game.default_options)
before = sound_replay(copied(state))
state[:round_eliminated]["Alice"] = true
assert(GameRoomSounds.result_cue(game, before, sound_replay(state), "Alice") == nil, "No Mercy round treated as match loss")

game = GameRoomGames::Domino.new
state = game.send(:initial_state, %w[Alice Bob Carol Dave], game.default_options)
state[:units] = { "team:1" => %w[Alice Carol], "team:2" => %w[Bob Dave] }
before = sound_replay(copied(state))
state[:eliminated]["team:1"] = true
assert(game.eliminated_from_game?(sound_replay(state), "Carol"), "team partner not eliminated")
state[:winner], state[:winners] = "Bob", %w[Bob Dave]
assert(GameRoomSounds.result_cue(game, before, sound_replay(state), "Dave") == "win_party", "team winner got loss")
state[:eliminated]["team:2"] = true
assert(GameRoomSounds.result_cue(game, before, sound_replay(state), "Dave") == "win_party", "simultaneous limit overrides final winner")

%w[holdem draw].each do |variant|
  game = GameRoomGames::Poker.new
  state = game.send(:initial_state, players, game.normalize_options("variant" => variant))
  state.update(phase: :betting, hands: { "Alice" => %w[AS AH], "Bob" => %w[KS KH], "Carol" => %w[QS QH] })
  before = sound_replay(copied(state))
  state[:stacks]["Alice"] = 0
  state[:all_in]["Alice"] = true
  assert(!game.eliminated_from_game?(sound_replay(state), "Alice"), "all-in treated as elimination")
  state[:phase] = :hand_complete
  after = sound_replay(copied(state))
  assert(GameRoomSounds.result_cue(game, before, after, "Alice") == "lose_party", "poker bust missing")
  state[:phase] = :betting
  state[:hands]["Alice"] = []
  assert(game.eliminated_from_game?(sound_replay(state), "Alice"), "poker bust forgotten next hand")
end

%w[farkle_bank ninety3366 1000_mariage win_party lose_party].each do |name|
  assert(GameRoomSounds::ASSET_NAMES.include?(name), "unregistered asset #{name}")
  assert(File.binread(File.expand_path("../../Audio/#{name}.opus", __dir__), 4) == "OggS", "invalid asset #{name}")
end

require_relative "../../lib/game_room_preferences"
program = Object.new
levels = { "sound_volumes" => { "all" => 50, "game" => 40, "notifications" => 100 } }
played = []
program.define_singleton_method(:game_room_sound_volume) { |name| GameRoomPreferences.sound_volume(levels, name) }
program.define_singleton_method(:play_sound_from_asset) { |name, volume:| played << [name, volume]; Object.new }
names = %w[play reverse draw2 ninety3366 farkle_bank 1000_mariage win_party lose_party]
GameRoomSounds.play_all(program, names)
assert(played == names.map { |name| [name, 0.2] }, "layered sounds lost cues or game/master volume")
levels["sound_volumes"]["game"] = 0
GameRoomSounds.play_all(program, names)
assert(played.length == names.length, "game mute failed for new sounds")
levels["sound_volumes"].merge!("game" => 100, "all" => 0)
GameRoomSounds.play_all(program, names)
assert(played.length == names.length, "master mute failed for new sounds")
puts "PASS post-228 sounds: accepted actions, overlapping cues, permanent/team eliminations, poker all-in and replay silence"
