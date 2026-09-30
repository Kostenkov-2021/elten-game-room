def _(text); text; end
require_relative "../../games/base"
require_relative "../../lib/game_sounds"

class NewSoundContractGame < GameRoomGames::Base
  attr_reader :received
  def id; 'new_game_without_framework_registration'; end
  def event_sound_cues(**data)
    @received = data
    %w[play buzzer2 play]
  end
end

def assert(value, message); raise message unless value; end
game = NewSoundContractGame.new
repository = Object.new
def repository.event_id(event); event['id']; end
event = {'id' => 71, 'action' => 'new_action'}.freeze
entries = [GameRoomGames::HistoryEntry.new(event_id: 70, kind: :move),
  GameRoomGames::HistoryEntry.new(event_id: 71, kind: :reshuffle)]
before = GameRoomGames::Replay.new(players: %w[Alice Bob], history: [], state: nil)
after = GameRoomGames::Replay.new(players: %w[Alice Bob], history: entries, state: nil, winner: 'Alice')
inputs = Marshal.dump([event, before, after])
sound_random = Random.new(19)
GameRoomSounds.instance_variable_set(:@sound_random, sound_random)
cues = GameRoomSounds.event_cue(game: game, event: event, before_replay: before,
  after_replay: after, repository: repository, viewer: 'Alice')
assert(cues == %w[card-shuffle play buzzer2 win_party], 'New game lost independent action/reshuffle/result cues or deduplication')
assert(game.received[:history] == entries.last(1), 'Model received history outside the presented event')
assert(game.received[:before_replay].state.nil? && game.received[:after_replay].state.nil?, 'Presentation requires a Hash for board state')
assert(game.received[:random_variant].call(%w[a b c]) == %w[a b c][Random.new(19).rand(3)], 'Cosmetic choice does not use the presenter-owned RNG')
assert(Marshal.dump([event, before, after]) == inputs, 'Sound projection mutated authoritative inputs')
assert(GameRoomGames::Base.new.event_sound_cues(**game.received).nil?, 'Games without action cues need special framework registration')

puts 'PASS model-owned sound hook: unknown game, event-local history, nil board state, multiple cues, result, dedup and cosmetic RNG'
