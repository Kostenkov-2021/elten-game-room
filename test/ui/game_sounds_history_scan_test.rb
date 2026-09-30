require_relative "../../lib/game_sounds"

def assert(value, message)
  raise message unless value
end

reads, passed = 0, []
entry_class = Struct.new(:id, :kind) do
  define_method(:event_id) { reads += 1; id }
end
history = Array.new(1000) { |index| entry_class.new(index, index == 999 ? :reshuffle : :play) }
replay = Struct.new(:history).new(history)
game = Object.new
game.define_singleton_method(:event_sound_cues) do |**options|
  passed << options.fetch(:history)
  ["play", "card-shuffle", "play"]
end
repository = Object.new
def repository.event_id(event); event; end
arguments = {game: game, event: 999, before_replay: nil, after_replay: replay,
  repository: repository, viewer: "Alice"}
assert(GameRoomSounds.event_cue(**arguments) == ["card-shuffle", "play"], "independent cue order/dedup changed")
assert(reads == 1000 && passed.last == [history.last], "event history scanned more than once")
reads = 0
assert(GameRoomSounds.action_cue(**arguments) == ["play", "card-shuffle", "play"], "standalone hook contract changed")
assert(reads == 1000, "standalone action_cue lost history fallback")
reads = 0
GameRoomSounds.action_cue(**arguments, history: [])
assert(reads.zero? && passed.last.empty?, "provided empty history was recomputed")
arguments[:event] = 998
GameRoomSounds.event_cue(**arguments)
assert(passed.last == [history[998]], "history leaked across events")
puts "PASS one history scan per sound event, standalone compatibility, empty history, independent cues and dedup"
